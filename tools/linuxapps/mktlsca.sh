#!/usr/bin/env bash
set -euo pipefail
DIR=${1:?output dir}
mkdir -p "$DIR"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$DIR/ca.key" -out "$DIR/ca.pem" -days 30 -subj "/CN=OsumTestCA" -addext "basicConstraints=critical,CA:TRUE" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -keyout "$DIR/leaf.key" -out "$DIR/leaf.csr" -subj "/CN=10.0.2.2" 2>/dev/null
printf 'subjectAltName=IP:10.0.2.2,IP:127.0.0.1\nbasicConstraints=CA:FALSE\n' > "$DIR/ext.cnf"
openssl x509 -req -in "$DIR/leaf.csr" -CA "$DIR/ca.pem" -CAkey "$DIR/ca.key" -CAcreateserial -out "$DIR/leaf.pem" -days 30 -extfile "$DIR/ext.cnf" 2>/dev/null
printf '{"policies":{"Certificates":{"Install":["/etc/osum-ca.pem"]}}}\n' > "$DIR/policies.json"
