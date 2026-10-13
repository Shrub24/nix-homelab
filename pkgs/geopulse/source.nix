{
  lib,
  fetchFromGitHub,
}:
# The GeoPulse release pin. The backend and the frontend build from this one
# revision, and `update.py` moves version, rev and hash together.
{
  version = "1.39.1";
  src = fetchFromGitHub {
    owner = "tess1o";
    repo = "geopulse";
    rev = "77e9c0eb071ac35674d40073b4b182e60bc3d176";
    hash = "sha256-Sps3FQsxayIUDs8Z6d4Y+7Ut/GI9oNzb4WJeHTotRa0=";
  };
}
