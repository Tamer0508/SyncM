/*
  Warnings:

  - You are about to drop the `SpotifyAccount` table. If the table is not empty, all the data it contains will be lost.

*/
-- DropForeignKey
ALTER TABLE "SpotifyAccount" DROP CONSTRAINT "SpotifyAccount_appUserId_fkey";

-- DropTable
DROP TABLE "SpotifyAccount";

-- CreateTable
CREATE TABLE "User" (
    "id" TEXT NOT NULL,
    "appUserId" TEXT,
    "spotifyId" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "email" TEXT,
    "avatarUrl" TEXT,
    "accessToken" TEXT,
    "refreshToken" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "User_appUserId_key" ON "User"("appUserId");

-- CreateIndex
CREATE UNIQUE INDEX "User_spotifyId_key" ON "User"("spotifyId");

-- AddForeignKey
ALTER TABLE "User" ADD CONSTRAINT "User_appUserId_fkey" FOREIGN KEY ("appUserId") REFERENCES "AppUser"("id") ON DELETE SET NULL ON UPDATE CASCADE;
