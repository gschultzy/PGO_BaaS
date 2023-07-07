#!/bin/bash

set -e
STARTTIME=$(date)
echo $STARTTIME

############################################
# Functions
#############################################

    # promnpt to continue
function prompt_continue() {
    read -p "Continue (y/n)?" choice
    case "$choice" in
    y|Y ) echo "yes";;
    n|N ) echo "no"; kill -- -$$;;
    * ) echo "invalid"; prompt_continue;;
    esac
}

    # prompt shell user name
SHELL_USER=$(whoami)
function shell_user() {
    read -p "whoami: " choice
    case "$choice" in
    $SHELL_USER ) echo $SHELL_USER;;
    * ) echo "invalid shell user"; kill -- -$$;;
    esac
}

    # tail the current postgreSQL instance log
function print_PGO_log() {

    PGDATA_VAR=$(oc -n $PGO_INSTANCE_NS exec $PGO_INSTANCE_POD -- sh -c "printenv | grep PGDATA")
    PGDATA_LOGDIR=$(echo $PGDATA_VAR | awk '{print substr($1,8)}')/log
    echo $PGDATA_LOGDIR
    PGDATA_LOGCURRENT=$(oc -n $PGO_INSTANCE_NS exec $PGO_INSTANCE_POD -- sh -c "ls -alt $PGDATA_LOGDIR" | awk 'FNR == 2 {print $9}')
    echo $PGDATA_LOGCURRENT
    oc -n $PGO_INSTANCE_NS exec $PGO_INSTANCE_POD -- sh -c "tail $PGDATA_LOGDIR/$PGDATA_LOGCURRENT"

}

############################################
# Gather Recovery info
#############################################

    # Create variables for script

RESTOREINSTNAME='hippo'
RESTOREDBNAME='hippo'
RESTORETABLENAME='hipposchema.myaccounts'
RESTOREUSER='postgres'
RESTOREPASSWORD='postgres'
PGO_RESTORE_INSTANCE_NS='postgres-restore'
PGO_INSTANCE_NS='postgres-operator'
PGO_INSTANCE_POD=$(oc -n $PGO_INSTANCE_NS get pods -l $PGO_INSTANCE_NS.crunchydata.com/role=master | awk 'FNR == 2 {print $1}')
RESTORESVC=$(oc get svc -n $PGO_INSTANCE_NS | grep $RESTOREINSTNAME-primary | awk 'FNR == 1 {print $1}')
RESTORETARGET=postgresql://${RESTOREUSER}:${RESTOREPASSWORD}@${RESTORESVC}.${PGO_RESTORE_INSTANCE_NS}.svc:5432/${RESTOREDBNAME}

echo
echo RESTOREINSTNAME = ${RESTOREINSTNAME}
echo RESTOREDBNAME = ${RESTOREDBNAME}
echo RESTORETABLENAME = ${RESTORETABLENAME}
echo RESTOREUSER = ${RESTOREUSER}
echo RESTOREPASSWORD = ${RESTOREPASSWORD}
echo PGO_RESTORE_INSTANCE_NS = ${PGO_RESTORE_INSTANCE_NS}
echo PGO_INSTANCE_NS = ${PGO_INSTANCE_NS}
echo PGO_INSTANCE_POD = ${PGO_INSTANCE_POD}
echo RESTORETARGET = ${RESTORETARGET}
echo RESTORESVC = ${RESTORESVC}
echo

    # prompt to continue
prompt_continue
    # get user to type user running the scipt
shell_user

###########################################
# In RESTORE ns
#############################################

    # set the postgres superuser temporary password
    # this is required as postgres superuser is is not automatically setup and we need it to setup the SUBSCRIPTION
echo
echo "Setting the postgres superuser temporary password"
echo
oc -n $PGO_RESTORE_INSTANCE_NS exec $PGO_INSTANCE_POD -- psql -c "\c $RESTOREDBNAME;" -c "ALTER USER postgres WITH PASSWORD 'postgres';"

    # create PUBLICATION 
echo
echo "Creating PUBLICATION"
echo
oc -n $PGO_RESTORE_INSTANCE_NS exec $PGO_INSTANCE_POD -- psql -c "\c $RESTOREDBNAME;" -c "CREATE PUBLICATION source FOR TABLE $RESTORETABLENAME;"

    # list PUBLICATIONS
echo    
oc -n $PGO_RESTORE_INSTANCE_NS exec $PGO_INSTANCE_POD -- psql -c "\c $RESTOREDBNAME;" -c "\dRp"

    # prompt user to confirm and continue with restore
    # prompt to continue
echo "########################################################################"
echo "#### Continuing on from here will overwrite the PRODUCTION database ####"
echo "########################################################################"
echo
    # prompt to continue
prompt_continue
    # get user to type user running the scipt
shell_user

echo
RESTORE_STARTTIME=$(date)
echo $RESTORE_STARTTIME
echo

############################################
# In PRODUCTION ns
#############################################

    # create SUBSCRIPTION
echo "Creating SUBSCRIPTION"
echo
oc -n $PGO_INSTANCE_NS exec $PGO_INSTANCE_POD -- psql -c "\c $RESTOREDBNAME;" -c "CREATE SUBSCRIPTION target CONNECTION '$RESTORETARGET' PUBLICATION source;"

    # list SUBSCRIPTIONS
echo
oc -n $PGO_INSTANCE_NS exec $PGO_INSTANCE_POD -- psql -c "\c $RESTOREDBNAME;" -c "\dRs"

    # check for data
oc -n $PGO_INSTANCE_NS exec $PGO_INSTANCE_POD -- psql -c "\c $RESTOREDBNAME;" -c "select * from $RESTORETABLENAME;"

    # prompt to validate data and then exit
l=0
while read -p "Can you see your data (y/n) OR Exit with log print (e)?" choice && [[ $choice != "Yes" ]] || [[ $choice != "Exit" ]]; do
   case $choice in
     y|Y ) echo "Yes"; break;;
     e|E ) echo "Exit"; l=1; break;;
     n|N ) echo "No";;
     * ) echo "invalid";;
   esac
   oc -n $PGO_INSTANCE_NS exec $PGO_INSTANCE_POD -- psql -c "\c $RESTOREDBNAME;" -c "select * from $RESTORETABLENAME;"
done
    # tail the current PostgreSQL instance log
echo $l
if [ $l -eq 1 ]
then
  print_PGO_log
fi
  
    # print end time stamp
echo
RESTORE_ENDTIME=$(date)
echo $RESTORE_ENDTIME
echo Restore complete!


