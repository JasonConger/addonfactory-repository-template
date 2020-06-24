#!/bin/bash
$REPOORG=splunk
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


while IFS=, read -r REPO TAID REPOVISIBILITY TITLE OTHER
do
    echo "Woring on:$REPO|$TAID|$REPOVISIBILITY|$TITLE|$OTHER"
    if ! gh repo view -R splunk/${REPO} >/dev/null
    then
        rm -rf work/$REPO
        echo Repository is new    
        mkdir -p work/$REPO || true
        cp -r seed/ work/$REPO
        cp -rf enforce/ work/$REPO
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
        git submodule add git@github.com:splunk/addonfactory_test_matrix_splunk.git deps/build/addonfactory_test_matrix_splunk
        git submodule add git@github.com:splunk/addonfactory-splunk_sa_cim.git deps/apps/Splunk_SA_CIM
        git submodule add git@github.com:splunk/addonfactory-splunk_env_indexer.git deps/apps/splunk_env_indexer

        git add .
        git commit -am "base"
        git tag -a v0.1.0 -m "CI base"        

        hub create -p splunk/$REPO
        hub api orgs/splunk/teams/products-shared-services-all/repos/splunk/$REPO --raw-field 'permission=maintain' -X PUT 
        hub api orgs/splunk/teams/productsecurity/repos/splunk/$REPO --raw-field 'permission=read' -X PUT 

        curl -X POST https://circleci.com/api/v1.1/project/github/splunk/$REPO/follow?circle-token=${CIRCLECI_TOKEN}
        curl -X POST --header "Content-Type: application/json" -d '{"type":"github-user-key"}' https://circleci.com/api/v1.1/project/github/splunk/$REPO/checkout-key?circle-token=${CIRCLECI_TOKEN}
        curl -X POST --header "Content-Type: application/json" -d "{\"name\":\"GH_USER\", \"value\":\"${GITHUB_USER}\"}" https://circleci.com/api/v1.1/project/github/splunk/$REPO/envvar?circle-token=${CIRCLECI_TOKEN}
        curl -X POST --header "Content-Type: application/json" -d "{\"name\":\"GITHUB_TOKEN\", \"value\":\"${GITHUB_TOKEN}\"}" https://circleci.com/api/v1.1/project/github/splunk/$REPO/envvar?circle-token=${CIRCLECI_TOKEN}

        git push --set-upstream origin master
        git tag -a v$(crudini --get package/default/app.conf launcher version) -m "Release"
        git push --follow-tags
        git checkout -b develop
        git push --set-upstream origin develop

    else
        echo Repository is existing
    fi
done < repositories.csv