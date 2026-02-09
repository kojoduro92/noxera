set -euo pipefail

# Ensure DB is up
docker compose -f infra/docker-compose.yml up -d

echo "✅ Granting MySQL privileges for Prisma shadow DB (dev)..."

docker compose -f infra/docker-compose.yml exec -T db mysql -uroot -proot -e "
CREATE USER IF NOT EXISTS 'noxera'@'%' IDENTIFIED BY 'noxera';
CREATE USER IF NOT EXISTS 'noxera'@'localhost' IDENTIFIED BY 'noxera';

-- Dev-only: allow Prisma to create shadow databases during migrate dev
GRANT ALL PRIVILEGES ON *.* TO 'noxera'@'%' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'noxera'@'localhost' WITH GRANT OPTION;

FLUSH PRIVILEGES;
"

echo "🎉 Done. User 'noxera' can now create Prisma shadow DBs."
