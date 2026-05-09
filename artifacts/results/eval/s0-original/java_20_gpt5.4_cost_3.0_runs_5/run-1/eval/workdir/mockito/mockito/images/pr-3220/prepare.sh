#!/bin/bash
set -e

cd /home/mockito
git reset --hard
bash /home/check_git_changes.sh
git checkout a0214364c36c840b259a4e5a0b656378e47d90df

# apply metamorphic patch (if present)


bash /home/check_git_changes.sh

./gradlew build || true

