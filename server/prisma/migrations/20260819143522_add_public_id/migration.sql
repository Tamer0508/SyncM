-- Публичный идентификатор пользователя: восемь символов алфавита Крокфорда.
--
-- Миграция в три шага, потому что колонка обязательная и уникальная, а
-- пользователи в базе уже есть. Одним ALTER TABLE с NOT NULL это не сделать:
-- существующим строкам нечего туда положить.

-- Шаг 0. Расширение для случайных байт.
--
-- gen_random_uuid() в Postgres 13+ встроен, а вот gen_random_bytes живёт в
-- pgcrypto. Без него миграция упадёт на шаге 2. IF NOT EXISTS: на части
-- окружений расширение уже включено.
--
-- Обойтись random() было бы можно, но он предсказуем — а по этому коду ищут
-- людей, и угадываемые значения позволили бы перебирать чужие профили.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Шаг 1. Добавляем колонку допускающей NULL.
ALTER TABLE "User" ADD COLUMN "publicId" TEXT;

-- Шаг 2. Заполняем существующие строки.
--
-- Генерация прямо в SQL, а не скриптом на Node: скрипт пришлось бы запускать
-- отдельно и не забыть про это на каждом окружении, а миграция выполняется
-- сама и ровно один раз.
--
-- Как это работает. gen_random_bytes(8) даёт восемь случайных байт;
-- get_byte вынимает каждый, остаток от деления на 32 выбирает символ
-- алфавита. Алфавит тот же, что в utils/publicId.js: цифры и латиница без
-- I, L, O и U.
--
-- Цикл нужен на случай совпадения: проверяем занятость и генерируем заново.
-- При триллионе сочетаний это почти невероятно, но «почти» в миграции —
-- недостаточное основание.
DO $$
DECLARE
  alphabet TEXT := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  target RECORD;
  candidate TEXT;
  raw BYTEA;
  i INT;
  taken BOOLEAN;
BEGIN
  FOR target IN SELECT "id" FROM "User" WHERE "publicId" IS NULL LOOP
    LOOP
      raw := gen_random_bytes(8);
      candidate := '';
      FOR i IN 0..7 LOOP
        candidate := candidate || substr(alphabet, (get_byte(raw, i) % 32) + 1, 1);
      END LOOP;

      SELECT EXISTS(SELECT 1 FROM "User" WHERE "publicId" = candidate) INTO taken;
      EXIT WHEN NOT taken;
    END LOOP;

    UPDATE "User" SET "publicId" = candidate WHERE "id" = target."id";
  END LOOP;
END $$;

-- Шаг 3. Теперь колонка заполнена — можно требовать её и вводить
-- уникальность.
ALTER TABLE "User" ALTER COLUMN "publicId" SET NOT NULL;
CREATE UNIQUE INDEX "User_publicId_key" ON "User"("publicId");