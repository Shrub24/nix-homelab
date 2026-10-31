{
  fetchFromGitHub,
}:
# The GeoPulse release pin. The backend and the frontend build from this one
# revision, and `update.py` moves version, rev and hash together.
{
  version = "2.1.1";
  src = fetchFromGitHub {
    owner = "tess1o";
    repo = "geopulse";
    rev = "5948c69e04935371c753a7e6fe81559917863af2";
    hash = "sha256-LxVjm6lDsNXpw5513fpZPQkWdoZOztqde0Q5hqAx7dc=";
  };
}
