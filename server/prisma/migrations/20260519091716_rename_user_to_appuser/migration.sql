/*
  Warnings:

  - You are about to drop the column `appUserId` on the `User` table. All the data in the column will be lost.
  - A unique constraint covering the columns `[senderId,receiverId]` on the table `Friendship` will be added. If there are existing duplicate values, this will fail.
  - A unique constraint covering the columns `[sessionId,userId]` on the table `SessionMember` will be added. If there are existing duplicate values, this will fail.
  - A unique constraint covering the columns `[trackId,userId]` on the table `TrackRating` will be added. If there are existing duplicate values, this will fail.
  - A unique constraint covering the columns `[app_user_id]` on the table `User` will be added. If there are existing duplicate values, this will fail.

*/
-- DropForeignKey
ALTER TABLE "User" DROP CONSTRAINT "User_appUserId_fkey";

-- DropIndex
DROP INDEX "User_appUserId_key";

-- AlterTable
ALTER TABLE "AppUser" ADD COLUMN     "friendsCount" INTEGER NOT NULL DEFAULT 0,
ADD COLUMN     "isFriendsHidden" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "isOnline" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "isOnlineHidden" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "lastSeenAt" TIMESTAMP(3),
ADD COLUMN     "sessionsCount" INTEGER NOT NULL DEFAULT 0;

-- AlterTable
ALTER TABLE "SessionTrack" ADD COLUMN     "addedById" TEXT,
ADD COLUMN     "durationMs" INTEGER;

-- AlterTable
ALTER TABLE "TrackRating" ADD COLUMN     "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ALTER COLUMN "rating" SET DEFAULT 1;

-- AlterTable
ALTER TABLE "User" DROP COLUMN "appUserId",
ADD COLUMN     "app_user_id" TEXT;

-- CreateTable
CREATE TABLE "Playlist" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "spotifyId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "imageUrl" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Playlist_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Playlist_spotifyId_key" ON "Playlist"("spotifyId");

-- CreateIndex
CREATE INDEX "Playlist_userId_idx" ON "Playlist"("userId");

-- CreateIndex
CREATE INDEX "AppUser_username_idx" ON "AppUser"("username");

-- CreateIndex
CREATE INDEX "EmailVerification_email_idx" ON "EmailVerification"("email");

-- CreateIndex
CREATE INDEX "EmailVerification_expiresAt_idx" ON "EmailVerification"("expiresAt");

-- CreateIndex
CREATE INDEX "Friendship_receiverId_status_idx" ON "Friendship"("receiverId", "status");

-- CreateIndex
CREATE INDEX "Friendship_senderId_status_idx" ON "Friendship"("senderId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "Friendship_senderId_receiverId_key" ON "Friendship"("senderId", "receiverId");

-- CreateIndex
CREATE INDEX "Session_isActive_idx" ON "Session"("isActive");

-- CreateIndex
CREATE INDEX "Session_hostId_createdAt_idx" ON "Session"("hostId", "createdAt");

-- CreateIndex
CREATE INDEX "SessionMember_sessionId_idx" ON "SessionMember"("sessionId");

-- CreateIndex
CREATE INDEX "SessionMember_userId_idx" ON "SessionMember"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "SessionMember_sessionId_userId_key" ON "SessionMember"("sessionId", "userId");

-- CreateIndex
CREATE INDEX "SessionTrack_sessionId_addedAt_idx" ON "SessionTrack"("sessionId", "addedAt");

-- CreateIndex
CREATE UNIQUE INDEX "TrackRating_trackId_userId_key" ON "TrackRating"("trackId", "userId");

-- CreateIndex
CREATE UNIQUE INDEX "User_app_user_id_key" ON "User"("app_user_id");

-- CreateIndex
CREATE INDEX "User_displayName_idx" ON "User"("displayName");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_app_user_id_fkey" FOREIGN KEY ("app_user_id") REFERENCES "AppUser"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Playlist" ADD CONSTRAINT "Playlist_userId_fkey" FOREIGN KEY ("userId") REFERENCES "AppUser"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SessionTrack" ADD CONSTRAINT "SessionTrack_addedById_fkey" FOREIGN KEY ("addedById") REFERENCES "AppUser"("id") ON DELETE SET NULL ON UPDATE CASCADE;
