#!/usr/bin/env bash

########################################################################################################################
########################################################################################################################

# NOTE: This script is not intended to be called directly.  It is
# called from the INSTALL_SUBMITTY.sh script that is generated by
# CONFIGURE_SUBMITTY.py.  That helper script initializes dozens of
# variables that are used in the code below.

# NEW NOTE: We are now ignoring most of the variables set in the
# INSTALL_SUBMITTY.sh script, and instead re-reading them from the
# config.json files when needed.  We wait to read most variables until
# the repos are updated and the necessary migrations are run.


# We assume a relative path from this repository to the installation
# directory and configuration directory.
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
CONF_DIR=${THIS_DIR}/../../../config

SUBMITTY_REPOSITORY=$(jq -r '.submitty_repository' ${CONF_DIR}/submitty.json)
SUBMITTY_INSTALL_DIR=$(jq -r '.submitty_install_dir' ${CONF_DIR}/submitty.json)

source ${THIS_DIR}/bin/versions.sh

DAEMONS=( submitty_autograding_shipper submitty_autograding_worker submitty_daemon_jobs_handler )

########################################################################################################################
########################################################################################################################
# this script must be run by root or sudo
if [[ "$UID" -ne "0" ]] ; then
    echo "ERROR: This script must be run by root or sudo"
    exit 1
fi

# check optional argument
if [[ "$#" -ge 1 && "$1" != "test" && "$1" != "clean" && "$1" != "test_rainbow" && "$1" != "restart_web" ]]; then
    echo -e "Usage:"
    echo -e "   ./INSTALL_SUBMITTY.sh"
    echo -e "   ./INSTALL_SUBMITTY.sh clean"
    echo -e "   ./INSTALL_SUBMITTY.sh clean test"
    echo -e "   ./INSTALL_SUBMITTY.sh clear test  <test_case_1>"
    echo -e "   ./INSTALL_SUBMITTY.sh clear test  <test_case_1> ... <test_case_n>"
    echo -e "   ./INSTALL_SUBMITTY.sh test"
    echo -e "   ./INSTALL_SUBMITTY.sh test  <test_case_1>"
    echo -e "   ./INSTALL_SUBMITTY.sh test  <test_case_1> ... <test_case_n>"
    echo -e "   ./INSTALL_SUBMITTY.sh test_rainbow"
    echo -e "   ./INSTALL_SUBMITTY.sh restart_web"
    exit 1
fi


########################################################################################################################
########################################################################################################################
# CLONE OR UPDATE THE HELPER SUBMITTY CODE REPOSITORIES

/bin/bash ${SUBMITTY_REPOSITORY}/.setup/bin/update_repos.sh

if [ $? -eq 1 ]; then
    echo -e "\nERROR: FAILURE TO CLONE OR UPDATE SUBMITTY HELPER REPOSITORIES\n"
    echo -e "Exiting INSTALL_SUBMITTY_HELPER.sh\n"
    exit 1
fi


################################################################################################################
################################################################################################################
# REMEMBER IF THE ANY OF OUR DAEMONS ARE ACTIVE BEFORE INSTALLATION BEGINS
# Note: We will stop & restart the daemons at the end of this script.
#       But it may be necessary to stop the the daemons as part of the migration.
for i in "${DAEMONS[@]}"; do
    systemctl is-active --quiet ${i}
    declare is_${i}_active_before=$?
done


################################################################################################################
################################################################################################################
# RUN THE SYSTEM AND DATABASE MIGRATIONS

if [ ${WORKER} == 0 ]; then
    echo -e 'Checking for system and database migrations'

    mkdir -p ${SUBMITTY_INSTALL_DIR}/migrations

    rsync -rtz ${SUBMITTY_REPOSITORY}/migration/migrations ${SUBMITTY_INSTALL_DIR}
    chown root:root ${SUBMITTY_INSTALL_DIR}/migrations
    chmod 550 -R ${SUBMITTY_INSTALL_DIR}/migrations

    python3 ${SUBMITTY_REPOSITORY}/migration/migrator.py migrate
fi


#############################################################
# Re-Read other variables from submitty.json and submitty_users.json
# (eventually will remove these from the /usr/local/submitty/.setup/INSTALL_SUBMITTY.sh script)

SUBMITTY_DATA_DIR=$(jq -r '.submitty_data_dir' ${SUBMITTY_INSTALL_DIR}/config/submitty.json)
COURSE_BUILDERS_GROUP=$(jq -r '.course_builders_group' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
NUM_UNTRUSTED=$(jq -r '.num_untrusted' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
FIRST_UNTRUSTED_UID=$(jq -r '.first_untrusted_uid' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
FIRST_UNTRUSTED_GID=$(jq -r '.first_untrusted_gid' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
NUM_GRADING_SCHEDULER_WORKERS=$(jq -r '.num_grading_scheduler_workers' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
DAEMON_USER=$(jq -r '.daemon_user' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
DAEMON_GROUP=${DAEMON_USER}
DAEMON_UID=$(jq -r '.daemon_uid' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
DAEMON_GID=$(jq -r '.daemon_gid' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
PHP_USER=$(jq -r '.php_user' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
PHP_UID=$(jq -r '.php_uid' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
PHP_GID=$(jq -r '.php_gid' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
CGI_USER=$(jq -r '.cgi_user' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
DAEMONPHP_GROUP=$(jq -r '.daemonphp_group' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)
DAEMONCGI_GROUP=$(jq -r '.daemoncgi_group' ${SUBMITTY_INSTALL_DIR}/config/submitty_users.json)

########################################################################################################################
########################################################################################################################

echo -e "\nBeginning installation of Submitty\n"


#this function takes a single argument, the name of the file to be edited
function replace_fillin_variables {
    sed -i -e "s|__INSTALL__FILLIN__SUBMITTY_REPOSITORY__|$SUBMITTY_REPOSITORY|g" $1
    sed -i -e "s|__INSTALL__FILLIN__SUBMITTY_INSTALL_DIR__|$SUBMITTY_INSTALL_DIR|g" $1
    sed -i -e "s|__INSTALL__FILLIN__SUBMITTY_DATA_DIR__|$SUBMITTY_DATA_DIR|g" $1
    sed -i -e "s|__INSTALL__FILLIN__CGI_USER__|$CGI_USER|g" $1
    sed -i -e "s|__INSTALL__FILLIN__PHP_USER__|$PHP_USER|g" $1
    sed -i -e "s|__INSTALL__FILLIN__DAEMON_USER__|$DAEMON_USER|g" $1
    sed -i -e "s|__INSTALL__FILLIN__DAEMONPHP_GROUP__|$DAEMONPHP_GROUP|g" $1
    sed -i -e "s|__INSTALL__FILLIN__COURSE_BUILDERS_GROUP__|$COURSE_BUILDERS_GROUP|g" $1

    sed -i -e "s|__INSTALL__FILLIN__NUM_UNTRUSTED__|$NUM_UNTRUSTED|g" $1
    sed -i -e "s|__INSTALL__FILLIN__FIRST_UNTRUSTED_UID__|$FIRST_UNTRUSTED_UID|g" $1
    sed -i -e "s|__INSTALL__FILLIN__FIRST_UNTRUSTED_GID__|$FIRST_UNTRUSTED_GID|g" $1

    sed -i -e "s|__INSTALL__FILLIN__DAEMON_UID__|$DAEMON_UID|g" $1
    sed -i -e "s|__INSTALL__FILLIN__DAEMON_GID__|$DAEMON_GID|g" $1
    sed -i -e "s|__INSTALL__FILLIN__PHP_UID__|$PHP_UID|g" $1
    sed -i -e "s|__INSTALL__FILLIN__PHP_GID__|$PHP_GID|g" $1
    sed -i -e "s|__INSTALL__FILLIN__CGI_UID__|$CGI_UID|g" $1
    sed -i -e "s|__INSTALL__FILLIN__CGI_GID__|$CGI_GID|g" $1

    sed -i -e "s|__INSTALL__FILLIN__TIMEZONE__|$TIMEZONE|g" $1

    sed -i -e "s|__INSTALL__FILLIN__DATABASE_HOST__|$DATABASE_HOST|g" $1
    sed -i -e "s|__INSTALL__FILLIN__DATABASE_USER__|$DATABASE_USER|g" $1
    sed -i -e "s|__INSTALL__FILLIN__DATABASE_PASSWORD__|$DATABASE_PASSWORD|g" $1

    sed -i -e "s|__INSTALL__FILLIN__SUBMISSION_URL__|$SUBMISSION_URL|g" $1
    sed -i -e "s|__INSTALL__FILLIN__VCS_URL__|$VCS_URL|g" $1
    sed -i -e "s|__INSTALL__FILLIN__CGI_URL__|$CGI_URL|g" $1
    sed -i -e "s|__INSTALL__FILLIN__SITE_LOG_PATH__|$SITE_LOG_PATH|g" $1

    sed -i -e "s|__INSTALL__FILLIN__AUTHENTICATION_METHOD__|${AUTHENTICATION_METHOD}|g" $1
    sed -i -e "s|__INSTALL__FILLIN__INSTITUTION__NAME__|$INSTITUTION_NAME|g" $1
    sed -i -e "s|__INSTALL__FILLIN__INSTITUTION__HOMEPAGE__|$INSTITUTION_HOMEPAGE|g" $1
    sed -i -e "s|__INSTALL__FILLIN__USERNAME__TEXT__|$USERNAME_CHANGE_TEXT|g" $1

    sed -i -e "s|__INSTALL__FILLIN__DEBUGGING_ENABLED__|$DEBUGGING_ENABLED|g" $1

    sed -i -e "s|__INSTALL__FILLIN__AUTOGRADING_LOG_PATH__|$AUTOGRADING_LOG_PATH|g" $1

    sed -i -e "s|__INSTALL__FILLIN__NUM_GRADING_SCHEDULER_WORKERS__|$NUM_GRADING_SCHEDULER_WORKERS|g" $1

    # FIXME: Add some error checking to make sure these values were filled in correctly
}


########################################################################################################################
########################################################################################################################
# if the top level INSTALL directory does not exist, then make it
mkdir -p ${SUBMITTY_INSTALL_DIR}


# option for clean install (delete all existing directories/files
if [[ "$#" -ge 1 && $1 == "clean" ]] ; then

    # pop this argument from the list of arguments...
    shift

    echo -e "\nDeleting submitty installation directories, ${SUBMITTY_INSTALL_DIR}, for a clean installation\n"

    # save the course index page
    originalcurrentcourses=/usr/local/submitty/site/app/views/current_courses.php
    if [ -f $originalcurrentcourses ]; then
        mytempcurrentcourses=`mktemp`
        echo "save this file! ${originalcurrentcourses} ${mytempcurrentcourses}"
        mv ${originalcurrentcourses} ${mytempcurrentcourses}
    fi

    rm -rf ${SUBMITTY_INSTALL_DIR}/site
    rm -rf ${SUBMITTY_INSTALL_DIR}/src
    rm -rf ${SUBMITTY_INSTALL_DIR}/bin
    rm -rf ${SUBMITTY_INSTALL_DIR}/sbin
    rm -rf ${SUBMITTY_INSTALL_DIR}/test_suite
    rm -rf ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools
fi

# set the permissions of the top level directory
chown  root:${COURSE_BUILDERS_GROUP}  ${SUBMITTY_INSTALL_DIR}
chmod  751                            ${SUBMITTY_INSTALL_DIR}

########################################################################################################################
########################################################################################################################
# if the top level DATA, COURSES, & LOGS directores do not exist, then make them

echo -e "Make top level SUBMITTY DATA directories & set permissions"

mkdir -p ${SUBMITTY_DATA_DIR}

if [ "${WORKER}" == 1 ]; then
    echo -e "INSTALLING SUBMITTY IN WORKER MODE"
else
    echo -e "INSTALLING PRIMARY SUBMITTY"
fi

#Make a courses and checkouts directory if not in worker mode.
if [ "${WORKER}" == 0 ]; then
    mkdir -p ${SUBMITTY_DATA_DIR}/courses
    mkdir -p ${SUBMITTY_DATA_DIR}/vcs
    mkdir -p ${SUBMITTY_DATA_DIR}/vcs/git
fi

mkdir -p ${SUBMITTY_DATA_DIR}/logs
mkdir -p ${SUBMITTY_DATA_DIR}/logs/autograding
mkdir -p ${SUBMITTY_DATA_DIR}/logs/emails

#Make site logging directories if not in worker mode.
if [ "${WORKER}" == 0 ]; then
    mkdir -p ${SUBMITTY_DATA_DIR}/logs/site_errors
    mkdir -p ${SUBMITTY_DATA_DIR}/logs/access
    mkdir -p ${SUBMITTY_DATA_DIR}/logs/ta_grading
fi

# set the permissions of these directories
chown  root:${COURSE_BUILDERS_GROUP}              ${SUBMITTY_DATA_DIR}
chmod  751                                        ${SUBMITTY_DATA_DIR}

#Set up courses and version control ownership if not in worker mode
if [ "${WORKER}" == 0 ]; then
    chown  root:${COURSE_BUILDERS_GROUP}              ${SUBMITTY_DATA_DIR}/courses
    chmod  751                                        ${SUBMITTY_DATA_DIR}/courses
    chown  root:${DAEMONCGI_GROUP}                    ${SUBMITTY_DATA_DIR}/vcs
    chmod  770                                        ${SUBMITTY_DATA_DIR}/vcs
    chown  root:${DAEMONCGI_GROUP}                    ${SUBMITTY_DATA_DIR}/vcs/git
    chmod  770                                        ${SUBMITTY_DATA_DIR}/vcs/git
fi

#Set up permissions on the logs directory. If in worker mode, PHP_USER does not exist.
if [ "${WORKER}" == 0 ]; then
    chown  -R ${PHP_USER}:${COURSE_BUILDERS_GROUP}  ${SUBMITTY_DATA_DIR}/logs
    chmod  -R u+rwx,g+rxs,o+x                         ${SUBMITTY_DATA_DIR}/logs
else
    chown  -R root:${COURSE_BUILDERS_GROUP}           ${SUBMITTY_DATA_DIR}/logs
    chmod  -R u+rwx,g+rxs,o+x                         ${SUBMITTY_DATA_DIR}/logs
fi

chown  -R ${DAEMON_USER}:${COURSE_BUILDERS_GROUP} ${SUBMITTY_DATA_DIR}/logs/autograding
chmod  -R u+rwx,g+rxs                             ${SUBMITTY_DATA_DIR}/logs/autograding

chown  -R ${DAEMON_USER}:${COURSE_BUILDERS_GROUP} ${SUBMITTY_DATA_DIR}/logs/emails
chmod  -R u+rwx,g+rxs                             ${SUBMITTY_DATA_DIR}/logs/emails

#Set up shipper grading directories if not in worker mode.
if [ "${WORKER}" == 0 ]; then
    # remove the old versions of the queues
    rm -rf $SUBMITTY_DATA_DIR/to_be_graded_interactive
    rm -rf $SUBMITTY_DATA_DIR/to_be_graded_batch
    # if the to_be_graded directories do not exist, then make them
    mkdir -p $SUBMITTY_DATA_DIR/to_be_graded_queue
    mkdir -p $SUBMITTY_DATA_DIR/daemon_job_queue

    # set the permissions of these directories
    # INTERACTIVE QUEUE: the PHP_USER will write items to this list, DAEMON_USER will remove them
    # BATCH QUEUE: course builders (instructors & head TAs) will write items to this list, DAEMON_USER will remove them
    chown  ${DAEMON_USER}:${DAEMONPHP_GROUP}        $SUBMITTY_DATA_DIR/to_be_graded_queue
    chmod  770                                      $SUBMITTY_DATA_DIR/to_be_graded_queue
    chown  ${DAEMON_USER}:${DAEMONPHP_GROUP}        $SUBMITTY_DATA_DIR/daemon_job_queue
    chmod  770                                      $SUBMITTY_DATA_DIR/daemon_job_queue
fi


# tmp folder
mkdir -p ${SUBMITTY_DATA_DIR}/tmp
chown root:root ${SUBMITTY_DATA_DIR}/tmp
chmod 511 ${SUBMITTY_DATA_DIR}/tmp

########################################################################################################################
########################################################################################################################
# RSYNC NOTES
#  a = archive, recurse through directories, preserves file permissions, owner  [ NOT USED, DON'T WANT TO MESS W/ PERMISSIONS ]
#  r = recursive
#  v = verbose, what was actually copied
#  t = preserve modification times
#  u = only copy things that have changed
#  z = compresses (faster for text, maybe not for binary)
#  (--delete, but probably dont want)
#  / trailing slash, copies contents into target
#  no slash, copies the directory & contents to target


########################################################################################################################
########################################################################################################################
# COPY THE CORE GRADING CODE (C++ files) & BUILD THE SUBMITTY GRADING LIBRARY

echo -e "Copy the grading code"

# copy the files from the repo
rsync -rtz ${SUBMITTY_REPOSITORY}/grading ${SUBMITTY_INSTALL_DIR}/src

#replace necessary variables
array=( Sample_CMakeLists.txt CMakeLists.txt system_call_check.cpp seccomp_functions.cpp execute.cpp )
for i in "${array[@]}"; do
    replace_fillin_variables ${SUBMITTY_INSTALL_DIR}/src/grading/${i}
done

# building the autograding library
mkdir -p ${SUBMITTY_INSTALL_DIR}/src/grading/lib
pushd ${SUBMITTY_INSTALL_DIR}/src/grading/lib
cmake ..
make
if [ $? -ne 0 ] ; then
    echo "ERROR BUILDING AUTOGRADING LIBRARY"
    exit 1
fi
popd > /dev/null

# root will be owner & group of these files
chown -R  root:root ${SUBMITTY_INSTALL_DIR}/src
# "other" can cd into & ls all subdirectories
find ${SUBMITTY_INSTALL_DIR}/src -type d -exec chmod 555 {} \;
# "other" can read all files
find ${SUBMITTY_INSTALL_DIR}/src -type f -exec chmod 444 {} \;

chgrp submitty_daemon ${SUBMITTY_INSTALL_DIR}/src/grading/python/submitty_router.py
chmod g+wrx ${SUBMITTY_INSTALL_DIR}/src/grading/python/submitty_router.py


#Set up sample files if not in worker mode.
if [ "${WORKER}" == 0 ]; then
    ########################################################################################################################
    ########################################################################################################################
    # COPY THE SAMPLE FILES FOR COURSE MANAGEMENT

    echo -e "Copy the sample files"

    # copy the files from the repo
    rsync -rtz ${SUBMITTY_REPOSITORY}/more_autograding_examples ${SUBMITTY_INSTALL_DIR}

    # root will be owner & group of these files
    chown -R  root:root ${SUBMITTY_INSTALL_DIR}/more_autograding_examples
    # but everyone can read all that files & directories, and cd into all the directories
    find ${SUBMITTY_INSTALL_DIR}/more_autograding_examples -type d -exec chmod 555 {} \;
    find ${SUBMITTY_INSTALL_DIR}/more_autograding_examples -type f -exec chmod 444 {} \;
fi
########################################################################################################################
########################################################################################################################
# BUILD JUNIT TEST RUNNER (.java file)

echo -e "Build the junit test runner"

# copy the file from the repo
rsync -rtz ${SUBMITTY_REPOSITORY}/junit_test_runner/TestRunner.java ${SUBMITTY_INSTALL_DIR}/JUnit/TestRunner.java

pushd ${SUBMITTY_INSTALL_DIR}/JUnit > /dev/null
# root will be owner & group of the source file
chown  root:root  TestRunner.java
# everyone can read this file
chmod  444 TestRunner.java

# compile the executable
javac -cp ./junit-4.12.jar TestRunner.java

# everyone can read the compiled file
chown root:root TestRunner.class
chmod 444 TestRunner.class

popd > /dev/null

########################################################################################################################
########################################################################################################################
# COPY VARIOUS SCRIPTS USED BY INSTRUCTORS AND SYS ADMINS FOR COURSE ADMINISTRATION

source ${SUBMITTY_REPOSITORY}/.setup/INSTALL_SUBMITTY_HELPER_BIN.sh

# build the helper program for strace output and restrictions by system call categories
g++ ${SUBMITTY_INSTALL_DIR}/src/grading/system_call_check.cpp -o ${SUBMITTY_INSTALL_DIR}/bin/system_call_check.out

# build the helper program for calculating early submission incentive extensions
g++ ${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.cpp -lboost_system -lboost_filesystem -std=c++11 -Wall -g -o ${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.out

# set the permissions
chown root:${COURSE_BUILDERS_GROUP} ${SUBMITTY_INSTALL_DIR}/bin/system_call_check.out
chmod 550 ${SUBMITTY_INSTALL_DIR}/bin/system_call_check.out

chown root:${COURSE_BUILDERS_GROUP} ${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.out
chmod 550 ${SUBMITTY_INSTALL_DIR}/bin/calculate_extensions.out


###############################################
# scripts used only by root for setup only
mkdir -p ${SUBMITTY_INSTALL_DIR}/.setup/bin
chown root:root ${SUBMITTY_INSTALL_DIR}/.setup/bin
chmod 700 ${SUBMITTY_INSTALL_DIR}/.setup/bin

cp  ${SUBMITTY_REPOSITORY}/.setup/bin/reupload_old_assignments.py   ${SUBMITTY_INSTALL_DIR}/.setup/bin/
cp  ${SUBMITTY_REPOSITORY}/.setup/bin/reupload_generate_csv.py   ${SUBMITTY_INSTALL_DIR}/.setup/bin/
cp  ${SUBMITTY_REPOSITORY}/.setup/bin/track_git_version.py   ${SUBMITTY_INSTALL_DIR}/.setup/bin/
chown root:root ${SUBMITTY_INSTALL_DIR}/.setup/bin/reupload*
chmod 700 ${SUBMITTY_INSTALL_DIR}/.setup/bin/reupload*
chown root:root ${SUBMITTY_INSTALL_DIR}/.setup/bin/track_git_version.py
chmod 700 ${SUBMITTY_INSTALL_DIR}/.setup/bin/track_git_version.py
replace_fillin_variables ${SUBMITTY_INSTALL_DIR}/.setup/bin/reupload_old_assignments.py

########################################################################################################################
########################################################################################################################
# PREPARE THE UNTRUSTED_EXEUCTE EXECUTABLE WITH SUID

# copy the file
rsync -rtz  ${SUBMITTY_REPOSITORY}/.setup/untrusted_execute.c   ${SUBMITTY_INSTALL_DIR}/.setup/
# replace necessary variables
replace_fillin_variables ${SUBMITTY_INSTALL_DIR}/.setup/untrusted_execute.c

# SUID (Set owner User ID up on execution), allows the $DAEMON_USER
# to run this executable as sudo/root, which is necessary for the
# "switch user" to untrusted as part of the sandbox.

pushd ${SUBMITTY_INSTALL_DIR}/.setup/ > /dev/null
# set ownership/permissions on the source code
chown root:root untrusted_execute.c
chmod 500 untrusted_execute.c
# compile the code
g++ -static untrusted_execute.c -o ${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute
# change permissions & set suid: (must be root)
chown root  ${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute
chgrp $DAEMON_USER  ${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute
chmod 4550  ${SUBMITTY_INSTALL_DIR}/sbin/untrusted_execute
popd > /dev/null


################################################################################################################
################################################################################################################
# COPY THE 1.0 Grading Website if not in worker mode
if [ ${WORKER} == 0 ]; then
    source ${SUBMITTY_REPOSITORY}/.setup/INSTALL_SUBMITTY_HELPER_SITE.sh
fi

################################################################################################################
################################################################################################################
# COMPILE AND INSTALL ANALYSIS TOOLS

echo -e "Compile and install analysis tools"

mkdir -p ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools

pushd ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools
if [[ ! -f VERSION || $(< VERSION) != "${AnalysisTools_Version}" ]]; then
    for b in count plagiarism diagnostics;
        do wget -nv "https://github.com/Submitty/AnalysisTools/releases/download/${AnalysisTools_Version}/${b}" -O ${b}
    done

    echo ${AnalysisTools_Version} > VERSION
fi
popd > /dev/null

# change permissions
chown -R ${DAEMON_USER}:${COURSE_BUILDERS_GROUP} ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools
chmod -R 555 ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools

# NOTE: These variables must match the same variables in install_system.sh
clangsrc=${SUBMITTY_INSTALL_DIR}/clang-llvm/src
clangbuild=${SUBMITTY_INSTALL_DIR}/clang-llvm/build
# note, we are not running 'ninja install', so this path is unused.
clanginstall=${SUBMITTY_INSTALL_DIR}/clang-llvm/install

ANALYSIS_TOOLS_REPO=${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/AnalysisTools

#copying commonAST scripts 
mkdir -p ${clangsrc}/llvm/tools/clang/tools/extra/ASTMatcher/
mkdir -p ${clangsrc}/llvm/tools/clang/tools/extra/UnionTool/

array=( astMatcher.py commonast.py unionToolRunner.py jsonDiff.py utils.py refMaps.py match.py eqTag.py context.py \
        removeTokens.py jsonDiffSubmittyRunner.py jsonDiffRunner.py jsonDiffRunnerRunner.py createAllJson.py )
for i in "${array[@]}"; do
    rsync -rtz ${ANALYSIS_TOOLS_REPO}/commonAST/${i} ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools
done

rsync -rtz ${ANALYSIS_TOOLS_REPO}/commonAST/unionTool.cpp ${clangsrc}/llvm/tools/clang/tools/extra/UnionTool/
rsync -rtz ${ANALYSIS_TOOLS_REPO}/commonAST/CMakeLists.txt ${clangsrc}/llvm/tools/clang/tools/extra/ASTMatcher/
rsync -rtz ${ANALYSIS_TOOLS_REPO}/commonAST/ASTMatcher.cpp ${clangsrc}/llvm/tools/clang/tools/extra/ASTMatcher/
rsync -rtz ${ANALYSIS_TOOLS_REPO}/commonAST/CMakeListsUnion.txt ${clangsrc}/llvm/tools/clang/tools/extra/UnionTool/CMakeLists.txt

#copying tree visualization scrips
rsync -rtz ${ANALYSIS_TOOLS_REPO}/treeTool/make_tree_interactive.py ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools
rsync -rtz ${ANALYSIS_TOOLS_REPO}/treeTool/treeTemplate1.txt ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools
rsync -rtz ${ANALYSIS_TOOLS_REPO}/treeTool/treeTemplate2.txt ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools

#building commonAST excecutable
pushd ${ANALYSIS_TOOLS_REPO}
g++ commonAST/parser.cpp commonAST/traversal.cpp -o ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/commonASTCount.out
g++ commonAST/parserUnion.cpp commonAST/traversalUnion.cpp -o ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/unionCount.out
popd > /dev/null

# building clang ASTMatcher.cpp
mkdir -p ${clanginstall}
mkdir -p ${clangbuild}
pushd ${clangbuild}
# TODO: this cmake only needs to be done the first time...  could optimize commands later if slow?
cmake .
# FIXME: skipping this step until we actually use it, since it's expensive
#ninja ASTMatcher UnionTool
popd > /dev/null

cp ${clangbuild}/bin/ASTMatcher ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/
cp ${clangbuild}/bin/UnionTool ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/
chmod o+rx ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/ASTMatcher
chmod o+rx ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools/UnionTool


# change permissions
chown -R ${DAEMON_USER}:${COURSE_BUILDERS_GROUP} ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools
chmod -R 555 ${SUBMITTY_INSTALL_DIR}/SubmittyAnalysisTools


#####################################
# Checkout the NLohmann C++ json library

nlohmann_dir=${SUBMITTY_INSTALL_DIR}/GIT_CHECKOUT/vendor/nlohmann/json

if [ ! -d "${nlohmann_dir}" ]; then
    git clone --depth 1 https://github.com/nlohmann/json.git ${nlohmann_dir}
fi


#####################################
# Build & Install Lichen Modules

/bin/bash ${SUBMITTY_REPOSITORY}/../Lichen/install_lichen.sh


################################################################################################################
################################################################################################################
# INSTALL PYTHON SUBMITTY UTILS

echo -e "Install python_submitty_utils"

pushd ${SUBMITTY_REPOSITORY}/python_submitty_utils
pip3 install .

# fix permissions
chmod -R 555 /usr/local/lib/python*/*
chmod 555 /usr/lib/python*/dist-packages

#Set up pam if not in worker mode.
if [ "${WORKER}" == 0 ]; then
    sudo chmod 500   /usr/local/lib/python*/dist-packages/pam.py*
    sudo chown ${CGI_USER} /usr/local/lib/python*/dist-packages/pam.py*
fi
sudo chmod o+r /usr/local/lib/python*/dist-packages/submitty_utils*.egg
sudo chmod o+r /usr/local/lib/python*/dist-packages/easy-install.pth

popd > /dev/null


################################################################################################################
################################################################################################################

installed_commit=$(jq '.installed_commit' /usr/local/submitty/config/version.json)
most_recent_git_tag=$(jq '.most_recent_git_tag' /usr/local/submitty/config/version.json)
echo -e "Completed installation of the Submitty version ${most_recent_git_tag//\"/}, commit ${installed_commit//\"/}\n"


################################################################################################################
################################################################################################################
# INSTALL & START GRADING SCHEDULER DAEMON
#############################################################
# stop the any of the submitty daemons (if they're running)
for i in "${DAEMONS[@]}"; do
    systemctl is-active --quiet ${i}
    is_active_now=$?
    if [[ "${is_active_now}" == "0" ]]; then
        systemctl stop ${i}
        echo -e "Stopped ${i}"
    fi
    systemctl is-active --quiet ${i}
    is_active_tmp=$?
    if [[ "$is_active_tmp" == "0" ]]; then
        echo -e "ERROR: did not successfully stop {$i}\n"
        exit 1
    fi
done

if [ "${WORKER}" == 0 ]; then
    # Stop all foreign worker daemons
    echo -e -n "Stopping worker machine daemons..."
    sudo -H -u ${DAEMON_USER} ${SUBMITTY_INSTALL_DIR}/sbin/shipper_utils/systemctl_wrapper.py stop --target perform_on_all_workers
    echo -e "done"
fi

#############################################################
# cleanup the TODO and DONE folders
original_autograding_workers=/var/local/submitty/autograding_TODO/autograding_worker.json
if [ -f $original_autograding_workers ]; then
    temp_autograding_workers=`mktemp`
    echo "save this file! ${original_autograding_workers} ${temp_autograding_workers}"
    mv ${original_autograding_workers} ${temp_autograding_workers}
fi

array=( autograding_TODO autograding_DONE )
for i in "${array[@]}"; do
    rm -rf ${SUBMITTY_DATA_DIR}/${i}
    mkdir -p ${SUBMITTY_DATA_DIR}/${i}
    chown -R ${DAEMON_USER}:${DAEMON_GID} ${SUBMITTY_DATA_DIR}/${i}
    chmod 770 ${SUBMITTY_DATA_DIR}/${i}
done

# return the autograding_workers json
if [ -f "$temp_autograding_workers" ]; then
    echo "return this file! ${temp_autograding_workers} ${original_autograding_workers}"
    mv ${temp_autograding_workers} ${original_autograding_workers}
fi

#############################################################
# update the various daemons

for i in "${DAEMONS[@]}"; do
    # update the autograding shipper & worker daemons
    rsync -rtz  ${SUBMITTY_REPOSITORY}/.setup/${i}.service  /etc/systemd/system/${i}.service
    chown -R ${DAEMON_USER}:${DAEMON_GROUP} /etc/systemd/system/${i}.service
    chmod 444 /etc/systemd/system/${i}.service
done

# delete the autograding tmp directories
rm -rf /var/local/submitty/autograding_tmp

# recreate the top level autograding tmp directory
mkdir /var/local/submitty/autograding_tmp
chown root:root /var/local/submitty/autograding_tmp
chmod 511 /var/local/submitty/autograding_tmp

# recreate the per untrusted directories
for ((i=0;i<$NUM_UNTRUSTED;i++));
do
    myuser=`printf "untrusted%02d" $i`
    mydir=`printf "/var/local/submitty/autograding_tmp/untrusted%02d" $i`
    mkdir $mydir
    chown ${DAEMON_USER}:$myuser $mydir
    chmod 770 $mydir
done

#Obtains the current git hash and tag and stores them in the appropriate jsons.
python3 ${SUBMITTY_INSTALL_DIR}/.setup/bin/track_git_version.py
chmod o+r ${SUBMITTY_INSTALL_DIR}/config/version.json


#############################################################################
# If the migrations have indicated that it is necessary to rebuild all
# existing gradeables, do so.

REBUILD_ALL_FILENAME=${SUBMITTY_INSTALL_DIR}/REBUILD_ALL_FLAG.txt

if [ -f $REBUILD_ALL_FILENAME ]; then
    echo -e "\n\nMigration has indicated that the code includes a breaking change for autograding"
    echo -e "\n\nMust rebuild ALL GRADEABLES\n\n"
    for s in /var/local/submitty/courses/*/*; do c=`basename $s`; ${s}/BUILD_${c}.sh --clean; done
    echo -e "\n\nDone rebuilding ALL GRADEABLES for ALL COURSES\n\n"
    rm $REBUILD_ALL_FILENAME
fi

#############################################################################

# Restart php-fpm and apache
if [ "${WORKER}" == 0 ]; then
    if [[ "$#" -ge 1 && $1 == "restart_web" ]]; then
        PHP_VERSION=$(php -r 'print PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
        echo -n "restarting php${PHP_VERSION}-fpm..."
        systemctl restart php${PHP_VERSION}-fpm
        echo "done"
        echo -n "restarting apache2..."
        systemctl restart apache2
        echo "done"
    fi
fi


# If any of our daemon files have changed, we should reload the units:
systemctl daemon-reload

# start the shipper daemon (if it was running)

for i in "${DAEMONS[@]}"; do
    is_active=is_${i}_active_before
    if [[ "${!is_active}" == "0" ]]; then
        systemctl start ${i}
        systemctl is-active --quiet ${i}
        is_active_after=$?
        if [[ "$is_active_after" != "0" ]]; then
            echo -e "\nERROR!  Failed to restart ${i}\n"
        fi
        echo -e "Restarted ${i}"
    else
        echo -e "\nNOTE: ${i} is not currently running\n"
        echo -e "To start the daemon, run:\n   sudo systemctl start ${i}\n"
    fi
done

################################################################################################################
################################################################################################################
# INSTALL TEST SUITE if not in worker mode
if [ "${WORKER}" == 0 ]; then
    # one optional argument installs & runs test suite
    if [[ "$#" -ge 1 && $1 == "test" ]]; then

        # copy the directory tree and replace variables
        echo -e "Install Autograding Test Suite..."
        rsync -rtz  ${SUBMITTY_REPOSITORY}/tests/  ${SUBMITTY_INSTALL_DIR}/test_suite
        mkdir -p ${SUBMITTY_INSTALL_DIR}/test_suite/log
        replace_fillin_variables ${SUBMITTY_INSTALL_DIR}/test_suite/integrationTests/lib.py

        # add a symlink to conveniently run the test suite or specific tests without the full reinstall
        ln -sf  ${SUBMITTY_INSTALL_DIR}/test_suite/integrationTests/run.py  ${SUBMITTY_INSTALL_DIR}/bin/run_test_suite.py

        echo -e "\nRun Autograding Test Suite...\n"

        # pop the first argument from the list of command args
        shift
        # pass any additional command line arguments to the run test suite
        python3 ${SUBMITTY_INSTALL_DIR}/test_suite/integrationTests/run.py  "$@"

        echo -e "\nCompleted Autograding Test Suite\n"
    fi
fi

################################################################################################################
################################################################################################################

# INSTALL RAINBOW GRADES TEST SUITE if not in worker mode
if [ "${WORKER}" == 0 ]; then
    # one optional argument installs & runs test suite
    if [[ "$#" -ge 1 && $1 == "test_rainbow" ]]; then

        # copy the directory tree and replace variables
        echo -e "Install Rainbow Grades Test Suite..."
        rsync -rtz  ${SUBMITTY_REPOSITORY}/tests/  ${SUBMITTY_INSTALL_DIR}/test_suite
        replace_fillin_variables ${SUBMITTY_INSTALL_DIR}/test_suite/rainbowGrades/test_sample.py

        # add a symlink to conveniently run the test suite or specific tests without the full reinstall
        #ln -sf  ${SUBMITTY_INSTALL_DIR}/test_suite/integrationTests/run.py  ${SUBMITTY_INSTALL_DIR}/bin/run_test_suite.py

        echo -e "\nRun Rainbow Grades Test Suite...\n"
        rainbow_counter=0
        rainbow_total=0

        # pop the first argument from the list of command args
        shift
        # pass any additional command line arguments to the run test suite
        rainbow_total=$((rainbow_total+1))
        python3 ${SUBMITTY_INSTALL_DIR}/test_suite/rainbowGrades/test_sample.py  "$@"
        
        if [[ $? -ne 0 ]]; then
            echo -e "\n[ FAILED ] sample test\n"
        else
            rainbow_counter=$((rainbow_counter+1))
            echo -e "\n[ SUCCEEDED ] sample test\n"
        fi

        echo -e "\nCompleted Rainbow Grades Test Suite. $rainbow_counter of $rainbow_total tests succeeded.\n"
    fi
fi

################################################################################################################
################################################################################################################
# confirm permissions on the repository (to allow push updates from primary to worker)
echo "Preparing to update Submitty installation on worker machines"
if [ "${WORKER}" == 1 ]; then
    # the supervisor user/group must have write access on the worker machine
    chgrp -R ${SUPERVISOR_USER} ${SUBMITTY_REPOSITORY}
    chmod -R g+rw ${SUBMITTY_REPOSITORY}
else
    # This takes a bit of time, let's skip if there are no workers
    num_machines=$(jq '. | length' /usr/local/submitty/config/autograding_workers.json)
    if [ "${num_machines}" != "1" ]; then
        # in order to update the submitty source files on the worker machines
        # the DAEMON_USER/DAEMON_GROUP must have read access to the repo on the primary machine
        chgrp -R ${DAEMON_GID} ${SUBMITTY_REPOSITORY}
        chmod -R g+r ${SUBMITTY_REPOSITORY}

        # Update any foreign worker machines
        echo -e Updating worker machines
        sudo -H -u ${DAEMON_USER} ${SUBMITTY_INSTALL_DIR}/sbin/shipper_utils/update_and_install_workers.py
    fi
fi
