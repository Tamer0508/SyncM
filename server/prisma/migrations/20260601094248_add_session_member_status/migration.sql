-- DropIndex
DROP INDEX "Playlist_spotifyId_key";

-- AlterTable
ALTER TABLE "Playlist" ADD COLUMN     "isCustom" BOOLEAN NOT NULL DEFAULT false,
ALTER COLUMN "spotifyId" DROP NOT NULL;

-- AlterTable
ALTER TABLE "SessionMember" ADD COLUMN     "status" TEXT NOT NULL DEFAULT 'pending';

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "customAvatarUrl" TEXT,
ADD COLUMN     "usernameChangedByUser" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "PlaylistTrack" (
    "id" TEXT NOT NULL,
    "playlistId" TEXT NOT NULL,
    "spotifyUri" TEXT NOT NULL,
    "trackName" TEXT NOT NULL,
    "artistName" TEXT NOT NULL,
    "durationMs" INTEGER,
    "addedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlaylistTrack_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LikedTrack" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "spotifyUri" TEXT NOT NULL,
    "trackName" TEXT NOT NULL,
    "artistName" TEXT NOT NULL,
    "likedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LikedTrack_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PlayHistory" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "spotifyUri" TEXT NOT NULL,
    "trackName" TEXT NOT NULL,
    "artistName" TEXT NOT NULL,
    "playedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "PlayHistory_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "PlaylistTrack_playlistId_spotifyUri_key" ON "PlaylistTrack"("playlistId", "spotifyUri");

-- CreateIndex
CREATE UNIQUE INDEX "LikedTrack_userId_spotifyUri_key" ON "LikedTrack"("userId", "spotifyUri");

-- CreateIndex
CREATE INDEX "PlayHistory_userId_playedAt_idx" ON "PlayHistory"("userId", "playedAt");

-- AddForeignKey
ALTER TABLE "PlaylistTrack" ADD CONSTRAINT "PlaylistTrack_playlistId_fkey" FOREIGN KEY ("playlistId") REFERENCES "Playlist"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "LikedTrack" ADD CONSTRAINT "LikedTrack_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PlayHistory" ADD CONSTRAINT "PlayHistory_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
