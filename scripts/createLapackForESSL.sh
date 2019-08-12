#!/bin/bash
# Adapted from IBM Engineering and Scientific Subroutine Library for Linux on POWER Version 6.2 ESSL Guide and Reference
#
# First Pass - get the symbols in ESSL and LAPACK
echo "The essl library is: " $1
echo "The lapack library is: " $2
echo "The output library is: liblapackforessl.a"
nm $2 | grep " T " | awk '{ print $3 }' | sort -n > symbols.in.lapack
nm $1 | grep " T " | awk '{ print $3 }' | sort -n > symbols.in.essl
diff -y symbols.in.lapack symbols.in.essl | grep -v -e '>' -e '|' -e '<'  | awk '{ print $1 }' > duplicate.symbols
wc -l duplicate.symbols

# Second Pass - remove the ESSL symbols from the LAPACK library
cp -p $2 liblapackforessl.a

for SYMBOL in $(cat duplicate.symbols | awk '{ print $1 }')
do
    fn=$SYMBOL
    unders="no"
    echo $SYMBOL | grep "_" > /dev/null && unders="yes"
    if [ "$unders" = "yes" ]
    then
        fn=`echo $SYMBOL | awk -F'_' '{print $1}'`
    fi

    echo $SYMBOL
    ar d liblapackforessl.a $fn.o
done

# Check it worked
nm liblapackforessl.a | grep " T " | awk '{ print $3 }' | sort -n > symbols.in.updatedlapack
diff -y symbols.in.updatedlapack symbols.in.essl | grep -v -e '>' -e '|' -e '<' | awk '{ print $1 }' > duplicate.symbols.inupdatedlapack
wc -l duplicate.symbols.inupdatedlapack
