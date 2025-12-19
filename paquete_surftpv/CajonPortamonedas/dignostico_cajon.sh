#!/bin/bash

IP="192.168.1.24"
PORT="9100"

echo "🔍 Iniciando diagnóstico..."

# Test de conexión
echo "1. Probando conexión..."
nc -zv $IP $PORT && echo "✅ Conexión OK" || echo "❌ Error conexión"

# Test de impresión simple
echo "2. Probando impresión..."
echo "TEST CAJON" | nc -w 2 $IP $PORT && echo "✅ Impresión OK" || echo "❌ Error impresión"

# Probar múltiples comandos
echo "3. Probando comandos de cajón..."

comandos=(
    '\x1B\x70\x00\x19\xFA'
    '\x1B\x70\x00'
    '\x1B\x70'
    '\x1Bp0'
    '\x1Bp\x00'
    '\x1B\x07'
    '\x10\x14\x01\x00\x00'
    '\x10\x14\x00\x00\x00'
    '\x1b\x70\x00\x3c\xf0'
)

for i in "${!comandos[@]}"; do
    echo "Probando comando $((i+1)): ${comandos[$i]}"
    echo -e "${comandos[$i]}" | nc -w 2 $IP $PORT
    sleep 1
done

echo "🎯 Diagnóstico completo"
