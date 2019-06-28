#!/usr/bin/env bash
#
check_time_sync()
{

OK=0
WARN=1
CRIT=2
# get the short hostname
HOST=`uname -n | awk -F. '{print $1}'`

# Seed the text string 
#TEXT="$HOST: check-time-sync: "
TEXT=""

LIMIT=$1
offset="unset"

#
# Check DNS resolution using existing servers in resolv.conf
#
#for NTPsrv in ntp1.ge.com ntp2.ge.com ntp3.ge.com ntp4.ge.com
#maybe one is enough?

for NTPsrv in ntp1.ge.com
do
  nslookup $NTPsrv 2>/dev/null > /tmp/gar.gar
  RC=$?
  if (( RC > 0 ))
  then
     TEXT="$TEXT: Can't resolve ntp1.ge.com. Exiting"
     echo $TEXT
     #exit $CRIT
     return $CRIT
  fi
  rm /tmp/gar.gar
done


for NTPsrv in ntp1.ge.com ntp2.ge.com ntp3.ge.com ntp4.ge.com
do
   # echo $NTPsrv
   # looking for transmitted with 0% packet loss
   YES=`ping $NTPsrv -c2 2>/dev/null| grep -i transmit | grep "0%"`
   #echo "YES: $YES"
   #As long as one of them can ping we'll get DNS=OK
   if [[ -n $YES ]]
   then
       #echo "Can ping $NTPsrv"
       DNS="OK"
   else
       TEXT="$TEXT: At least one NTP server failed ping."
   fi

done

# Is ntpd running?

IsNtpd=`ps -ef | grep ntpd | grep -v grep | wc -l`

if (( $IsNtpd < 1 ))
then

 ##echo "ntpd not running. Are we running chronyd"

 IsChrony=`ps -ef | grep chronyd | grep -v grep | wc -l`

 if (( $IsChrony < 1 ))
 then
    TEXT="$TEXT: Neither ntpd nor chronyd running. Exiting"
    #exit $CRIT
    return $CRIT
 else
    # chronyd running
    # echo "Yes server seems to be running chronyd"
    YES=`chronyc tracking | grep Reference | grep "ge.com"`
    if [[ -n $YES ]]
    then
      #echo "Time source exists:"
      #chronyc tracking | grep Reference | grep "ge.com"
      #strtm=`chronyc tracking | grep -i stratum | awk -F: '{print $2}'`
      #echo "Stratum: $strtm"
      #chronyc tracking | grep "System time"
      OffBy=`chronyc tracking | grep "System time" | awk '{print $4}'`
      # echo "OffBy: $OffBy"
      # This is in seconds. Converting to ms
#Dimitry: bc is not installed on all systems, replacing by awk
#      offset=`echo "$OffBy * 1000" | bc`
      offset=`awk -v num=$OffBy 'BEGIN {print num*1000}'`
      # if offset is negative, make it positive
      # c=`echo "$offset > 0.0" | bc`
      c=`awk -v num=$offset 'BEGIN {print (num<0?"0":"1")}'`
      if [[ $c == 0 ]]
      then
         #echo "offset: $offset"
         #echo "negative offset"
         #negative offset - remove minus sign
         offset=${offset#-}
         #echo $offset
       fi

      # echo "offset: $offset in ms"
      # let us check if it's gt LIMIT ms. Don't have to deal with old 'bc'
#      c=`echo "$offset > $LIMIT" | bc`
      c=`awk -v num1=$offset -v num2=$LIMIT 'BEGIN {print (num1>num2?"1":"0")}'`
      # c is 1 if true else false!
      if [[ $c = 1 ]]
      then
          #echo "$offset > $LIMIT"
          ADD=" > $LIMIT ms. FAILURE! Exceeds threshold"
          TEXT="$TEXT time sync offset=$offset ms $ADD"
          echo $TEXT
          return $CRIT
      else
          #echo "$offset <= $LIMIT"
          ADD=" <= $LIMIT ms. OK"
          TEXT="$TEXT time sync offset=$offset ms $ADD"
          echo $TEXT
          return $OK
      fi
    else #not GE reference
      TEXT="$TEXT WARNING! chrony service is not referenced to GE ntp servers."
      echo $TEXT
      return $WARN
    fi # chronyd time source exists
 fi # chrony running

else
   # ok ntpd is running. do we have ntpq?
   # can get offset from ntpq or ntpdate
   ##echo "ntpd running. Let us proceed with normal case"
   #

   ##echo "ntpd IS running. Let us check ntpq first"

   # Get the current time source: line with '*' as the first char
   # if it exists, get stratum and offset

   if [ -f /usr/sbin/ntpq ]
   then
     SrcLine=`/usr/sbin/ntpq -pn 2>/dev/null | grep "*"`
     if [[ -z $SrcLine ]]
     then
         TEXT="$TEXT: Warning: no time source found from ntpq\n"
     else
         #echo "time source exists in ntpq output"
         # ntpq gives offset in millisec
         #echo $SrcLine
         #strtm=`/usr/sbin/ntpq -pn | grep "*" | awk '{print $3}'`
         offset=`/usr/sbin/ntpq -pn | grep "*" | awk '{print $9}'`

         # if offset is negative, make it positive
#         c=`echo "$offset > 0.0" | bc`
          c=`awk -v num=$offset 'BEGIN {print (num<0?"0":"1")}'`
         if [[ $c == 0 ]]
         then
           #echo "offset: $offset"
           #echo "negative offset"
           #negative offset - remove minus sign
           offset=${offset/#-/}
           #echo $offset
         fi

         # let us check if it's gt LIMIT ms. Have to deal with old 'bc'
#         c=`echo "if ($offset > $LIMIT) 1" | bc`
         c=`awk -v num1=$offset -v num2=$LIMIT 'BEGIN {print (num1>num2?"1":"0")}'`
         # c is 1 if true else undefined!
         if [[ $c = 1 ]]
         then
             #echo "$offset > $LIMIT"
             ADD=" > $LIMIT ms. FAILURE! Exceeds threshold"
             TEXT="$TEXT time sync offset=$offset ms $ADD"
             echo $TEXT
             return $CRIT
         else
             #echo "$offset <= $LIMIT"
             ADD=" <= $LIMIT ms. OK"
             TEXT="$TEXT time sync offset=$offset ms $ADD"
             echo $TEXT
             return $OK
         fi
     fi
   fi

   # if we can't get offset from ntpq then let us try from ntpdate
   if ( [[ $offset = "unset" ]] && [[ $DNS = "OK" ]] )
   then

      if [[ -f /usr/sbin/ntpdate ]]
      then
         TEXT="$TEXT Checking ntpdate"
         # ntpdate gives offset in seconds. convert to ms to be consistent
         offsets=`/usr/sbin/ntpdate -q ntp1.ge.com ntp2.ge.com ntp3.ge.com ntp4.ge.com | grep ntpdate | tail -1 | awk '{print $(NF-1)}'`
#         offset=`echo "$offsets * 1000" | bc`
         offset=`awk -v num=$offsets 'BEGIN {print num*1000}'`

         # if offset is negative, make it positive
#         c=`echo "$offset > 0.0" | bc`
          c=`awk -v num=$offset 'BEGIN {print (num<0?"0":"1")}'`
         if [[ $c == 0 ]]
         then
           #echo "offset: $offset"
           #echo "negative offset"
           #negative offset - remove minus sign
           offset=${offset#-}
           #echo $offset
         fi

         # let us check if it's gt LIMIT ms. 
#         c=`echo "$offset > $LIMIT" | bc`
          c=`awk -v num1=$offset -v num2=$LIMIT 'BEGIN {print (num1>num2?"1":"0")}'`
         # c is 1 if true else undefined!
         if [[ $c = 1 ]]
         then
              #echo "$offset > $LIMIT"
              ADD=" > $LIMIT ms. FAILURE! Exceeds threshold"
              TEXT="$TEXT time sync offset=$offset ms $ADD"
              echo $TEXT
              return $CRIT
         else
             #echo "$offset <= $LIMIT"
             ADD=" <= $LIMIT ms. OK"
             TEXT="$TEXT time sync offset=$offset ms $ADD"
             echo $TEXT
             return $OK
         fi

      else # ntpdate not found
         TEXT="$TEXT ntpdate not found. Both ntpq and ntpdate failed. Exiting"
         echo $TEXT
         return $CRIT
      fi # if ntpdate exists
    fi
fi

}


# Main

USAGE="$0 <Threshold-in-ms>"

if (($# > 1))
then
   echo
   echo "Too many args"
   echo "$USAGE"
   echo
   exit
elif  (($# == 1))
then
   LIMIT=$1
   # echo
   # echo "Detected argument: $LIMIT"
else
   # no arg. Will assume 500 ms
   # echo
   # echo "No argument detected. Assuming 500 ms as default threshold"
   LIMIT=500.0
fi

# echo "calling check_time_sync with $LIMIT ms as threshold"
# echo

ANS="$(check_time_sync $LIMIT)"
RC=$?

# One echo for all
#echo "$ANS: Return-Code: $RC"
echo -e "$ANS"
exit $RC
