#!/bin/sh

# Tenter de curl localhost:8081
curl -sSf http://localhost:8081

# Si curl échoue, sortir avec le code d'erreur de curl
if [ $? -ne 0 ]; then
  echo "Error: Unable to reach localhost:8081"
  exit 1
fi

# Si curl réussit, sortir avec succès
echo "Success: Reached localhost:8081"
exit 0