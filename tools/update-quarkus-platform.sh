#!/usr/bin/env bash
set -euo pipefail

GITHUB_URL="https://github.com/"
GITHUB_URL_SSH="git@github.com:"

MINOR_VERSION=
DRY_RUN=false
BRANCH=main

usage() {
    echo 'Usage: update-quarkus-platform.sh -v $MINOR_VERSION -f $FORK [-s] [-b] [-n] COMMAND'
    echo
    echo 'Options:'
    echo '  -v $MINOR_VERSION    set MINOR version'
    echo '                       e.g. 6.0.Final for Kogito 1.6.0.Final and OptaPlanner 8.6.0.Final'
    echo '  -f $FORK             GH account where the branch should be pushed'
    echo '  -s                   Use SSH to connect to GitHub'
    echo '  -b $BRANCH           Quarkus Platform branch (optional. Default is `main`)'
    echo '  -n                   no execution: clones, creates the branch, but will not push or create the PR'
    echo '  COMMAND              may be `stage` or `finalize`'
    echo
    echo 'Examples:'#!/bin/sh
    echo '  # Stage the PR'
    echo '  #  - Bump Kogito 1.7.0.Final + OptaPlanner 8.7.0.Final'
    echo '  #  - Add staging repositories'
    echo '  #  - Push the branch to evacchi/quarkus-platform'
    echo '  #  - Dry Run'
    echo '  sh update-quarkus-platform.sh -v 7.0.Final -f evacchi -n stage'
    echo
    echo '  # Finalize the PR:'
    echo '  #  - Remove staging repositories'
    echo '  #  - Force-push the branch to evacchi/quarkus-platform'
    echo '  #  - Dry Run'
    echo '  sh update-quarkus-platform.sh -v 7.0.Final -f evacchi -n finalize'
}

args=`getopt v:f:b:snh $*`
if [ "$#" -eq 0 -o $? != 0 ]; then
    >&2 echo ERROR: no args given.

    usage
    exit 2
fi
set -- $args
for i
do
        case "$i"
        in
                -v)
                        MINOR_VERSION=$2;
                        shift;shift ;;
                -f)
                        FORK=$2
                        shift;shift ;;
                -s)     
                        GITHUB_URL=${GITHUB_URL_SSH}
                        shift;;
                -b)     
                        BRANCH=$2
                        shift;shift ;;
                -n)     
                        DRY_RUN=true
                        shift;;
                -h)     
                        usage;
                        exit 0;
                        ;;
                --)
                        COMMAND=$2
                        shift; shift
                        ;;
                            
        esac
done


if [ "$MINOR_VERSION" = "" ]; then 
        >&2 echo ERROR: no version specified.
        usage

        exit 2
fi

if [ "$FORK" = "" ]; then 
        >&2 echo ERROR: no fork specified.
        usage

        exit 2
fi

case "$COMMAND"
in
    stage)
        COMMAND=stage
        ;;
    finalize)
        COMMAND=finalize
        ;;
    *)
        >&2 echo ERROR: invalid command $COMMAND.
        usage

        exit 2
esac

REPO=quarkus-platform
PR_FORK=$FORK/$REPO
ORIGIN=quarkusio/$REPO

KOGITO_VERSION=1.$MINOR_VERSION
OPTAPLANNER_VERSION=8.$MINOR_VERSION

PR_BRANCH=bump-kogito-$KOGITO_VERSION+optaplanner-$OPTAPLANNER_VERSION


echo GITHUB_URL...............$GITHUB_URL
echo ORIGIN...................$ORIGIN
echo PR_FORK..................$PR_FORK
echo BRANCH...................$BRANCH
echo PR_BRANCH................$PR_BRANCH
echo KOGITO_VERSION...........$KOGITO_VERSION
echo OPTAPLANNER_VERSION......$OPTAPLANNER_VERSION
echo COMMAND..................$COMMAND
echo
if [ "$DRY_RUN" = "true" ]; then
echo DRY_RUN! No changes will be pushed!
echo
fi


stage() {
    set -x

    git clone ${GITHUB_URL}${ORIGIN}
    cd $REPO

    # ensure main branch
    git checkout $BRANCH
    # create branch
    git checkout -b $PR_BRANCH
    # process versions
    ./mvnw \
    versions:set-property \
    -Dproperty=kogito-quarkus.version \
    -DnewVersion=$KOGITO_VERSION \
    -DgenerateBackupPoms=false
    ./mvnw \
    versions:set-property \
    -Dproperty=optaplanner-quarkus.version \
    -DnewVersion=$OPTAPLANNER_VERSION \
    -DgenerateBackupPoms=false
    
    # update pom metadata
    ./mvnw validate -Pregen-kogito -N
    
    # add custom repositories
    echo "$DIFF_FILE" | patch pom.xml

    ./mvnw -Dsync
    
    # commit all
    git commit -am "Kogito $KOGITO_VERSION + OptaPlanner $OPTAPLANNER_VERSION"

    if [ "$DRY_RUN" = "false" ]; then
        # push the branch to a remote
        git push -u ${GITHUB_URL}$PR_FORK $PR_BRANCH
        # Open a PR to kogito-runtimes using the commit as a title
        gh pr create --fill --base $BRANCH -R $ORIGIN
    fi
}

finalize() {
    set -x

    if [ -d "$REPO" ]; then
        cd $REPO
    else
        git clone ${GITHUB_URL}$PR_FORK
        cd $REPO;
    fi

    git checkout $PR_BRANCH



    # undo patch to add repos
    echo "$DIFF_FILE" | patch -R pom.xml

    ./mvnw process-resources

    # overwrite old commit (no need to squash)
    git commit --amend --no-edit pom.xml
    
    if [ "$DRY_RUN" = "false" ]; then
        # push forced (we are overwriting the old commit)
        git push --force-with-lease
    fi
}

DIFF_FILE='diff --git a/pom.xml b/pom.xml
index 98dcf3da..2d927f65 100644
--- a/pom.xml
+++ b/pom.xml
@@ -478,6 +478,15 @@
     </build>

     <repositories>
+        <repository>
+            <snapshots>
+                <enabled>false</enabled>
+            </snapshots>
+            <id>kogito</id>
+            <name>kogito</name>
+            <url>https://repository.jboss.org/nexus/content/groups/kogito-public/</url>
+        </repository>
+
         <repository>
             <id>confluent</id>
             <url>https://packages.confluent.io/maven/</url>
'
# execute
$COMMAND
