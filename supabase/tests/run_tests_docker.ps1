# Runs the PostgreSQL suite in a throwaway postgres:16 container.
# Usage: powershell -File supabase\tests\run_tests_docker.ps1
$ErrorActionPreference = 'Stop'
$supabase = (Resolve-Path "$PSScriptRoot\..").Path
$name = "foodbook-pgtest-$PID"

docker run -d --rm --name $name -e POSTGRES_PASSWORD=test -v "${supabase}:/work:ro" postgres:16 | Out-Null
try {
  for ($i = 0; $i -lt 60; $i++) {
    docker exec $name pg_isready -q -U postgres 2>$null
    if ($LASTEXITCODE -eq 0) { Start-Sleep -Seconds 2; break }
    Start-Sleep -Seconds 1
  }
  # Work on an LF copy: the scripts must not carry CRLF line endings.
  docker exec $name bash -c "mkdir -p /t && cp -r /work/. /t/ && find /t -name '*.sh' -o -name '*.sql' | xargs sed -i 's/\r$//' && chmod -R a+rX /t && chmod +x /t/tests/*.sh && /t/tests/run_tests.sh"
  $code = $LASTEXITCODE
  docker cp "${name}:/t/tests/LAST_RUN.txt" "$supabase\tests\LAST_RUN.txt" 2>$null
} finally {
  docker rm -f $name | Out-Null
}
exit $code
