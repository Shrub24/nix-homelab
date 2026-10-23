{
  fetchFromGitHub,
}:
# The GeoPulse release pin. The backend and the frontend build from this one
# revision, and `update.py` moves version, rev and hash together.
{
  version = "2.0.0";
  src = fetchFromGitHub {
    owner = "tess1o";
    repo = "geopulse";
    rev = "11955ec8e6046b58f3c90c6a53d6b66af58696c9";
    hash = "sha256-+oAEpv8vG2gI83V5GMIpdqXLSNrPOZiILaN6ZUZNZpM=";
  };
}
