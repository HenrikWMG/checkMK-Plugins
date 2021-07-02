#!/bin/bash

# get some binaries
WGET=$(which wget)
MD5SUM=$(which md5sum)
AWK=$(which awk)
ECHO=$(which echo)

# show help
usage(){
echo "Usage: $0 [-h]"}
echo "      -h                                       Show this Help"
echo "      -s <IP/FQDN:PORT> [-s <IP/FQDN:PORT>]    Sockets to ask. Can occur several times                "
echo "      -U <URL>                                 URL to reqest                                          "
echo "      -V <VIRTUAL HOST>                        The Virtualhost to put into the header of HTTP Request "
echo "      -X <HEADER LINE>  [-X <HEADER LINE> ]    Header Lines to add into the HTTP Request              "
echo "                                               Can occur several times                                "
}

# Declare Global Arrays
declare -a header_array=()
declare -a socket_array=()
declare -a checksum_array=()
declare -a checksum_array_returns=() 
declare -a pluginOutput_array=()
checkstatus=0

# load parameters
while getopts "s:hU:V:X:" opt; do
  case $opt in

    s) 
    set -f # disable glob
    socket_array+=("$OPTARG") ;;

    U) 
      URL=("$OPTARG")     
      ;;

    V) 
      #virtual_host=("$OPTARG") 
      header_array+=("--header=host: $OPTARG")    
      ;;

    X)
    set -f # disable glob
    header_array+=("--header=$OPTARG")
    ;;

    h) 
      usage
      exit 1     
      ;;

    \?)
      $ECHO "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;

    :)
      $ECHO "Option -$OPTARG requires an argument." >&2
      usage
      exit 1
      ;;
  esac
done


getHTTPcontent(){
        wgetContent=$($WGET --tries 1 -T 1 -nv -q -O - "${header_array[@]}" http://$1$2)
        
        # Catch Networkproblems 
        # https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html
        if [ $? -eq 4 ]; then
                $ECHO "URL not reachable"
                return 104
        fi

        if [ $? -eq 5 ]; then
                $ECHO "SSL Error"
                return 105
        fi

        if [ $? -ne 0 ]; then
                $ECHO "Return of WGET not 0"
                return 100
        fi

        echo "$wgetContent"
}

# ÜbergabeParameter 
#       - $1=Any String
makeChecksumMD5(){
        local checksum=""
        checksum=$(echo "$1" | $MD5SUM | $AWK '{print $1}')
        $ECHO "$checksum"
}

######### Main-Programm ############

# Iterate through all given Sockets and write Returncodes and Checksums to global arrays
for i in "${socket_array[@]}"; do
  
  # Get HTTP Content from a given Socket
  tmp_wgetContent=$(getHTTPcontent "${i}" "$URL")
  tmp_return="$?"

  # Make return persisent for later inspection
  checksum_array_returns+=("$tmp_return")

  # Catch errors from getHTTPcontent Function and write them to checksum_array
  if [ $tmp_return -ne 0 ]; then

    if [ $tmp_return -eq 104  ]; then
      checksum_array+=("URL not reachable")

    elif [ $tmp_return -eq 105  ]; then
      checksum_array+=("SSL Error")

    elif [ $tmp_return -eq 100  ]; then
      checksum_array+=("Unknown Error")
    fi

  # Only Create Checksum if Return of getHTTPContent zero
  else
    checksum_array+=("$(makeChecksumMD5 "$tmp_wgetContent")")
  fi 

  # Reset tmp-Variables for next Loop
  tmp_return=""
  tmp_wgetContent=""
done

# If one Value of checksum_array_returns is nonzero this
# automatically means WARN
for i in "${!checksum_array_returns[@]}"; do
  

  if [ "${checksum_array_returns[$i]}" -ne 0 ] ; then
    checkstatus=1
  fi
done

# Compare Checksums, set Status if necessary AND built the Output
reference_checksum=""
for i in "${!checksum_array[@]}"; do
  
  # First Checksum is Reference for all comparisons
  if [ $i -eq 0 ] ; then
    reference_checksum="${checksum_array[$i]}"
  fi

  # Compare with reference_checksum. Set Checkstatus to WARN if not equals
  if [ "${reference_checksum}" != "${checksum_array[$i]}" ]; then
    checkstatus=1
  fi

  # Built the Output for the Script. Must be 1 Line
  pluginOutput_array+=("Host: ${socket_array[$i]} Result: ${checksum_array[$i]}")

done

# End Script and make Output
echo "${pluginOutput_array[@]}" 
exit $checkstatus