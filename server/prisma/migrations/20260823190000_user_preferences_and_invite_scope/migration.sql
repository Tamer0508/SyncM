-- Настройки пользователя, которых до сих пор не было в базе.
--
-- allowSessionInvites: раньше приглашать в сессию мог любой друг, и отказаться
-- от приглашений было нельзя вовсе. Проверка живёт на сервере (см.
-- sessionController.createSession) — клиент такое ограничение соблюдать не
-- может по определению.
--
-- preferences: одна JSON-колонка на все настройки, которые не участвуют в
-- запросах, — уведомления и оформление. Колонка на переключатель означала бы
-- миграцию на каждую галочку; всё, что решает доступ к данным (isSearchHidden
-- и соседи), осталось отдельными колонками, потому что по ним ходят фильтры.

CREATE TYPE "InviteScope" AS ENUM ('friends', 'nobody');

ALTER TABLE "User"
  ADD COLUMN "allowSessionInvites" "InviteScope" NOT NULL DEFAULT 'friends',
  ADD COLUMN "preferences" JSONB NOT NULL DEFAULT '{}';
