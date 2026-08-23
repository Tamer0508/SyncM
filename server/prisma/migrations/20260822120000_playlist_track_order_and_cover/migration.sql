-- Обложка трека и ручной порядок внутри плейлиста.
--
-- Две вещи, которых не хватало пользовательским плейлистам, чтобы быть
-- полноценными, а не списком строк.
--
-- imageUrl: у треков из Spotify обложка приходит вместе с остальными полями,
-- но сохранять её было некуда — и в собственном плейлисте те же самые треки
-- показывались серыми квадратами с нотой.
--
-- position: список всегда шёл по addedAt. Время добавления — не то, что
-- человек двигает пальцем, и переставить трек было физически нечем.

ALTER TABLE "PlaylistTrack" ADD COLUMN "imageUrl" TEXT;
ALTER TABLE "PlaylistTrack" ADD COLUMN "position" INTEGER NOT NULL DEFAULT 0;

-- Заполняем порядок для уже существующих строк.
--
-- Без этого шага у всех треков остался бы position = 0, сортировка по нему
-- дала бы произвольный порядок, и первое же открытие плейлиста перетасовало
-- бы список у людей на глазах. Берём тот порядок, который они видели до сих
-- пор — по времени добавления, — и записываем его номерами.
--
-- id в ORDER BY вторым ключом: addedAt у пакетно добавленных треков
-- совпадает с точностью до миллисекунды, и без него нумерация была бы
-- недетерминированной.
WITH ordered AS (
  SELECT
    "id",
    ROW_NUMBER() OVER (PARTITION BY "playlistId" ORDER BY "addedAt" ASC, "id" ASC) - 1 AS rn
  FROM "PlaylistTrack"
)
UPDATE "PlaylistTrack" AS pt
SET "position" = ordered.rn
FROM ordered
WHERE pt."id" = ordered."id";

CREATE INDEX "PlaylistTrack_playlistId_position_idx" ON "PlaylistTrack"("playlistId", "position");
