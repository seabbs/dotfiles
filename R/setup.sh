#!bin/bash

bash python/setup.sh

brew install --cask r

pip3 install radian

cp R/.Rprofile ~/.Rprofile

Rscript R/packages.R
