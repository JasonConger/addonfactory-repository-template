#!/bin/bash
REPOORG=splunk
if [[  $GITHUB_USER && ${GITHUB_USER-x} ]]
then
    echo "GITHUB_USER Found" 
else
    echo "GITHUB_USER Not found"
    exit 1
fi
if [[  $GITHUB_TOKEN && ${GITHUB_TOKEN-x} ]]
then
    echo "GITHUB_TOKEN Found"
else
    echo "GITHUB_TOKEN Not found"
    exit 1
fi
if [[  $CIRCLECI_TOKEN && ${CIRCLECI_TOKEN-x} ]]
then
    echo "GITHUB_USER Found" 
else
    echo "GITHUB_USER Not found"
    exit 1
fi

command -v hub >/dev/null 2>&1 || { echo >&2 "I require hub but it's not installed.  Aborting."; exit 1; }
command -v gh >/dev/null 2>&1 || { echo >&2 "I require gh but it's not installed.  Aborting."; exit 1; }
command -v git >/dev/null 2>&1 || { echo >&2 "I require git but it's not installed.  Aborting."; exit 1; }
command -v crudini >/dev/null 2>&1 || { echo >&2 "I require crudini but it's not installed.  Aborting."; exit 1; }
command -v jq >/dev/null 2>&1 || { echo >&2 "I require jq but it's not installed.  Aborting."; exit 1; }
command -v rsync >/dev/null 2>&1 || { echo >&2 "I require rsync but it's not installed.  Aborting."; exit 1; }

while IFS=, read -r REPO TAID REPOVISIBILITY TITLE OTHER
do
    echo "Woring on:$REPO|$TAID|$REPOVISIBILITY|$TITLE|$OTHER"
    if ! gh repo view -R $REPOORG/${REPO} >/dev/null
    then
        rm -rf work/$REPO
        echo Repository is new    
        mkdir -p work/$REPO || true
        rsync -avh --include ".*" ../../seed/ .
        rsync -avh --include ".*" ../../enforce/ .
        pushd work/$REPO
        
        crudini --set package/default/app.conf launcher description "$TITLE"
        crudini --set package/default/app.conf ui label "$TITLE"
        crudini --set package/default/app.conf package id $TAID
        crudini --set package/default/app.conf id name $TAID
        
        tmpf=$(mktemp) 
        jq --arg TITLE "${TITLE}" '.info.title = $TITLE' package/app.manifest >$tmpf
        mv -f $tmpf package/app.manifest
        tmpf=$(mktemp) 
        jq --arg TITLE "${TITLE}" '.info.description = $TITLE' package/app.manifest >$tmpf
        mv -f $tmpf package/app.manifest
        jq --arg TAID "${TAID}" '.info.id.name = $TAID' package/app.manifest >$tmpf
        mv -f $tmpf package/app.manifest

        git init
        git config  user.email "addonfactory@splunk.com"
        git config  user.name "Addon Factory template"
        git submodule add git@github.com:$REPOORG/addonfactory_test_matrix_splunk.git deps/build/addonfactory_test_matrix_splunk
        git submodule add git@github.com:$REPOORG/addonfactory-splunk_sa_cim.git deps/apps/Splunk_SA_CIM
        git submodule add git@github.com:$REPOORG/addonfactory-splunk_env_indexer.git deps/apps/splunk_env_indexer

        git add .
        git commit -am "base"
        git tag -a v0.2.0 -m "CI base"        

        hub create -p $REPOORG/$REPO
        hub api orgs/$REPOORG/teams/products-shared-services-all/repos/$REPOORG/$REPO --raw-field 'permission=maintain' -X PUT 
        hub api orgs/$REPOORG/teams/productsecurity/repos/$REPOORG/$REPO --raw-field 'permission=read' -X PUT 

        curl -X POST https://circleci.com/api/v1.1/project/github/$REPOORG/$REPO/follow?circle-token=${CIRCLECI_TOKEN}
        curl -X POST --header "Content-Type: application/json" -d '{"type":"github-user-key"}' https://circleci.com/api/v1.1/project/github/$REPOORG/$REPO/checkout-key?circle-token=${CIRCLECI_TOKEN}
        curl -X POST --header "Content-Type: application/json" -d "{\"name\":\"GH_USER\", \"value\":\"${GITHUB_USER}\"}" https://circleci.com/api/v1.1/project/github/$REPOORG/$REPO/envvar?circle-token=${CIRCLECI_TOKEN}
        curl -X POST --header "Content-Type: application/json" -d "{\"name\":\"GITHUB_TOKEN\", \"value\":\"${GITHUB_TOKEN}\"}" https://circleci.com/api/v1.1/project/github/$REPOORG/$REPO/envvar?circle-token=${CIRCLECI_TOKEN}

        git remote set-url origin https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$REPOORG/$REPO.git
        git push --set-upstream origin master
        git tag -a v$(crudini --get package/default/app.conf launcher version) -m "Release"
        git push --follow-tags
        git checkout -b develop
        git push --set-upstream origin develop
        
    else
        echo Repository is existing
        if [ ! -d "$REPO" ]; then
            hub clone $REPOORG/$REPO work/$REPO
            pushd work/$REPO
            git checkout develop
        else
            pushd work/$REPO
            git pull
        fi                

        # Update any files in enforce
        rsync -avh --include ".*" --ignore-existing ../../seed/ .
        rsync -avh --include ".*" ../../enforce/ .
        git config  user.email "addonfactory@splunk.com"
        git config  user.name "Addon Factory template"
        git add .
        git commit -am "sync for policy"   
        #git push

    fi
    popd
done < repositories.csv