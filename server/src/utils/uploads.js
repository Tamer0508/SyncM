const path = require('path');

function isOwnedUploadName(fileName, ownerId) {
  if (!fileName || !ownerId) return false;
  return fileName.startsWith(`${ownerId}_`);
}

function resolveOwnedUploadPath(url, { dir, pathPrefix, ownerId, skipFileName = null }) {
  if (!url) return null;

  let pathname;
  try {
    pathname = new URL(url).pathname;
  } catch {
    pathname = url.startsWith('/') ? url : null;
  }
  if (!pathname) return null;

  if (!pathname.startsWith(pathPrefix)) return null;

  const name = path.basename(pathname);
  if (!name || name === skipFileName) return null;

  if (!isOwnedUploadName(name, ownerId)) return null;

  const resolved = path.resolve(dir, name);
  if (resolved !== path.join(dir, name)) return null;
  if (!resolved.startsWith(dir + path.sep)) return null;

  return resolved;
}

module.exports = { isOwnedUploadName, resolveOwnedUploadPath };
