#!bin/bash

cp ssh/config ~/.ssh/config

docker context create epiforecasts --docker "host=ssh://epiforecasts/epiforecasts"
