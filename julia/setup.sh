#!/bin/bash 

brew install --cask julia

echo 'alias julia=julia --threads 4' >> ~/.zshrc
echo 'export JULIA_NUM_THREADS=4' >> ~/.zshrc
