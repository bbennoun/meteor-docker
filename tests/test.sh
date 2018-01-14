set -e
docker build -t zodern/meteor:test ../meteor

command -v meteor >/dev/null 2>&1 || { curl https://install.meteor.com/ | sh; }

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ]
. "$NVM_DIR/nvm.sh"

rm -rf /tmp/docker-meteor-tests
mkdir /tmp/docker-meteor-tests
cp -r ../ /tmp/docker-meteor-tests
cd /tmp/docker-meteor-tests/tests

rm -rf ./app
rm -rf ./bundle
rm -rf ./archive
mkdir ./app
mkdir ./bundle
mkdir ./archive

docker rm -f meteor-docker-test >/dev/null || true

change_version() {
  echo "=> Creating app with $1"

  cd ..
  rm -rf app
  meteor create $1 app >/dev/null
  cd app
  sleep 1

  echo "=> npm install babel-runtime"
  meteor npm install babel-runtime -q || true
}

build_app() {
  echo "=> Building app"
  meteor build ../bundle --debug
}

build_app_directory() {
  echo "=> Building app"
  meteor build --directory --debug ../bundle
}

test_bundle() {
  echo "=> Archiving bundle"

  # rm -rf ./archive/*
  # tar -zcf ../archive/bundle.tar.gz ../bundle
  mv ../bundle/app.tar.gz ../bundle/bundle.tar.gz

  echo "=> Creating docker container"

  docker run \
    -v $PWD/../bundle:/bundle \
    -e "ROOT_URL=http://localhost.com" \
    -e "NPM_INSTALL_OPTIONS=--no-bin-links" \
    -p 3000:3000 \
    -d \
    --name meteor-docker-test \
    zodern/meteor:test
}

test_built() {
  NODE_VERSION=$(meteor node --version)
  NPM_VERSION=$(meteor npm --version)
  echo "NODE_VERSION=$NODE_VERSION"
  echo "NPM_VERSION=$NPM_VERSION"
  nvm install $NODE_VERSION >/dev/null
  nvm use $NODE_VERSION --silent
  npm i -g npm@$NPM_VERSION -q
 cd ../bundle/bundle/programs/server && npm install -q
 cd ../../../../app

 docker run \
  -v $PWD/../bundle/bundle:/built_app \
  -e "ROOT_URL=http://localhost.com" \
  -p 3000:3000 \
  -d \
  --name meteor-docker-test \
  zodern/meteor:test
}

verify() {
  TIMEOUT=120
  elaspsed=0
  success=0

  while [[ "$elaspsed" != "$TIMEOUT" && $success == 0 ]]; do
    sleep 1
    elaspsed=$((elaspsed+1))

    curl -s \
      localhost:3000 >/dev/null \
      && success=1
            
  done

  if [ "$success" == "0" ]; then
    echo "FAIL"
    docker logs meteor-docker-test --tail 150
    exit 1
  fi

  echo "SUCCESS $success"
  docker rm -f meteor-docker-test >/dev/null || true
}

test_version() {
  change_version $1

  build_app
  test_bundle
  verify

  build_app_directory
  test_built $1
  verify
}

test_version "--release=1.2.1"
test_version "--release=1.3.5.1"
# test_version "--release=1.4"
# test_version "--release=1.4.4.5"
test_version "--release=1.5.4.1"
test_version "--release=1.6"

# Latest version
test_version