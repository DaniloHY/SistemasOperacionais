#!/bin/sh
# Compila o programa e testa os quatro casos

zig build-exe main.zig || exit 1

head -c 510 /dev/zero > le.img && printf '\x55\xAA' >> le.img
head -c 510 /dev/zero > be.img && printf '\xAA\x55' >> be.img
head -c 512 /dev/zero > nada.img
head -c 100 /dev/zero > pequeno.img

echo "== Caso 1: le.img (55 AA) =="
./main le.img
echo "== Caso 2: be.img (AA 55) =="
./main be.img
echo "== Caso 3: nada.img (sem assinatura) =="
./main nada.img
echo "== Caso 4: pequeno.img (menos de 512 bytes) =="
./main pequeno.img
