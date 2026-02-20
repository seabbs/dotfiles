#!/bin/bash

xcode-select --install

bash brew/setup.sh
bash scripts/common-tools.sh
bash mac/apps.sh
