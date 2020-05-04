#!/bin/sh -e
#
# Copyright (C) Internet Systems Consortium, Inc. ("ISC")
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# See the COPYRIGHT file distributed with this work for additional
# information regarding copyright ownership.

# shellcheck source=conf.sh
. "$SYSTEMTESTTOP/conf.sh"

echo_i "ns3/setup.sh"

setup() {
	zone="$1"
	echo_i "setting up zone: $zone"
	zonefile="${zone}.db"
	infile="${zone}.db.infile"
	echo "$zone" >> zones
}

private_type_record() {
	_zone=$1
	_algorithm=$2
	_keyfile=$3

	_id=$(keyfile_to_key_id "$_keyfile")

	printf "%s. 0 IN TYPE65534 %s 5 %02x%04x0000\n" "$_zone" "\\#" "$_algorithm" "$_id"
}

# Set in the key state files the Predecessor/Successor fields.
# Key $1 is the predecessor of key $2.
key_successor() {
	id1=$(keyfile_to_key_id "$1")
	id2=$(keyfile_to_key_id "$2")
	echo "Predecessor: ${id1}" >> "${2}.state"
	echo "Successor: ${id2}" >> "${1}.state"
}

# Make lines shorter by storing key states in environment variables.
H="HIDDEN"
R="RUMOURED"
O="OMNIPRESENT"
U="UNRETENTIVE"

#
# Set up zones that will be initially signed.
#
for zn in default rsasha1 dnssec-keygen some-keys legacy-keys pregenerated \
	  rumoured rsasha1-nsec3 rsasha256 rsasha512 ecdsa256 ecdsa384 \
	  dynamic dynamic-inline-signing inline-signing \
	  inherit unlimited
do
	setup "${zn}.kasp"
	cp template.db.in "$zonefile"
done

# Set up zone that stays unsigned.
zone="unsigned.kasp"
echo_i "setting up zone: $zone"
zonefile="${zone}.db"
infile="${zone}.db.infile"
cp template.db.in $zonefile

# Some of these zones already have keys.
zone="dnssec-keygen.kasp"
$KEYGEN -k rsasha1 -l policies/kasp.conf $zone > keygen.out.$zone.1 2>&1

zone="some-keys.kasp"
$KEYGEN -G -a RSASHA1 -b 2000 -L 1234 $zone > keygen.out.$zone.1 2>&1
$KEYGEN -G -a RSASHA1 -f KSK  -L 1234 $zone > keygen.out.$zone.2 2>&1

zone="legacy.kasp"
$KEYGEN -a RSASHA1 -b 2000 -L 1234 $zone > keygen.out.$zone.1 2>&1
$KEYGEN -a RSASHA1 -f KSK  -L 1234 $zone > keygen.out.$zone.2 2>&1

zone="pregenerated.kasp"
$KEYGEN -G -k rsasha1 -l policies/kasp.conf $zone > keygen.out.$zone.1 2>&1
$KEYGEN -G -k rsasha1 -l policies/kasp.conf $zone > keygen.out.$zone.2 2>&1

zone="rumoured.kasp"
Tpub="now"
Tact="now+1d"
keytimes="-P ${Tpub} -A ${Tact}"
KSK=$($KEYGEN  -a RSASHA1 -f KSK  -L 1234 $keytimes $zone 2> keygen.out.$zone.1)
ZSK1=$($KEYGEN -a RSASHA1 -b 2000 -L 1234 $keytimes $zone 2> keygen.out.$zone.2)
ZSK2=$($KEYGEN -a RSASHA1         -L 1234 $keytimes $zone 2> keygen.out.$zone.3)
$SETTIME -s -g $O -k $R $Tpub -r $R $Tpub -d $H $Tpub  "$KSK"  > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $R $Tpub -z $R $Tpub              "$ZSK1" > settime.out.$zone.2 2>&1
$SETTIME -s -g $O -k $R $Tpub -z $R $Tpub              "$ZSK2" > settime.out.$zone.2 2>&1

#
# Set up zones that are already signed.
#

# These signatures are set to expire long in the past, update immediately.
setup expired-sigs.autosign
T="now-6mo"
ksktimes="-P $T -A $T -P sync $T"
zsktimes="-P $T -A $T"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 300 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 300        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -d $O $T -k $O $T -r $O $T "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $T -z $O $T          "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -PS -x -s now-2mo -e now-1mo -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# These signatures are still good, and can be reused.
setup fresh-sigs.autosign
T="now-6mo"
ksktimes="-P $T -A $T -P sync $T"
zsktimes="-P $T -A $T"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 300 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 300        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -d $O $T -k $O $T -r $O $T "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $T -z $O $T          "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# These signatures are still good, but not fresh enough, update immediately.
setup unfresh-sigs.autosign
T="now-6mo"
ksktimes="-P $T -A $T -P sync $T"
zsktimes="-P $T -A $T"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 300 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 300        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -d $O $T -k $O $T -r $O $T "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $T -z $O $T          "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1w -e now+1w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# These signatures are already expired, and the private ZSK is missing.
setup zsk-missing.autosign
T="now-6mo"
ksktimes="-P $T -A $T -P sync $T"
zsktimes="-P $T -A $T"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 300 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 300        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -d $O $T -k $O $T -r $O $T "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $T -z $O $T          "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -PS -x -s now-2w -e now-1mi -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1
rm -f "${ZSK}".private

# These signatures are already expired, and the private ZSK is retired.
setup zsk-retired.autosign
T="now-6mo"
ksktimes="-P $T -A $T -P sync $T"
zsktimes="-P $T -A $T -I now"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 300 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 300        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -d $O $T -k $O $T -r $O $T "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $T -z $O $T          "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -PS -x -s now-2w -e now-1mi -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1
$SETTIME -s -g HIDDEN "$ZSK" > settime.out.$zone.3 2>&1

#
# The zones at enable-dnssec.autosign represent the various steps of the
# initial signing of a zone.
#

# Step 1:
# This is an unsigned zone and named should perform the initial steps of
# introducing the DNSSEC records in the right order.
setup step1.enable-dnssec.autosign
cp template.db.in $zonefile

# Step 2:
# The DNSKEY has been published long enough to become OMNIPRESENT.
setup step2.enable-dnssec.autosign
# DNSKEY TTL:             300 seconds
# zone-propagation-delay: 5 minutes (300 seconds)
# publish-safety:         5 minutes (300 seconds)
# Total:                  900 seconds
TpubN="now-900s"
# RRSIG TTL:              12 hour (43200 seconds)
# zone-propagation-delay: 5 minutes (300 seconds)
# retire-safety:          20 minutes (1200 seconds)
# Already passed time:    -900 seconds
# Total:                  43800 seconds
TsbmN="now+43800s"
keytimes="-P ${TpubN} -P sync ${TsbmN} -A ${TpubN}"
CSK=$($KEYGEN -k enable-dnssec -l policies/autosign.conf $keytimes $zone 2> keygen.out.$zone.1)
$SETTIME -s -g $O -k $R $TpubN -r $R $TpubN -d $H $TpubN -z $R $TpubN "$CSK" > settime.out.$zone.1 2>&1
cat template.db.in "${CSK}.key" > "$infile"
private_type_record $zone 13 "$CSK" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 3:
# The zone signatures have been published long enough to become OMNIPRESENT.
setup step3.enable-dnssec.autosign
# Passed time since publications: 43800 + 900 = 44700 seconds.
TpubN="now-44700s"
# The key is secure for using in chain of trust when the DNSKEY is OMNIPRESENT.
TcotN="now-43800s"
# We can submit the DS now.
TsbmN="now"
keytimes="-P ${TpubN} -P sync ${TsbmN} -A ${TpubN}"
CSK=$($KEYGEN -k enable-dnssec -l policies/autosign.conf $keytimes $zone 2> keygen.out.$zone.1)
$SETTIME -s -g $O -k $O $TcotN -r $O $TcotN -d $H $TpubN -z $R $TpubN "$CSK" > settime.out.$zone.1 2>&1
cat template.db.in "${CSK}.key" > "$infile"
private_type_record $zone 13 "$CSK" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1
setup step3.enable-dnssec.autosign

# Step 4:
# The DS has been submitted long enough ago to become OMNIPRESENT.
setup step4.enable-dnssec.autosign
# DS TTL:                    1 day (86400 seconds)
# parent-registration-delay: 1 day (86400 seconds)
# parent-propagation-delay:  1 hour (3600 seconds)
# retire-safety:             20 minutes (1200 seconds)
# Total aditional time:      98400 seconds
# 44700 + 98400 = 143100
TpubN="now-143100s"
# 43800 + 98400 = 142200
TcotN="now-142200s"
TsbmN="now-98400s"
keytimes="-P ${TpubN} -P sync ${TsbmN} -A ${TpubN}"
CSK=$($KEYGEN -k enable-dnssec -l policies/autosign.conf $keytimes $zone 2> keygen.out.$zone.1)
$SETTIME -s -g $O -k $O $TcotN -r $O $TcotN -d $R $TsbmN -z $O $TsbmN "$CSK" > settime.out.$zone.1 2>&1
cat template.db.in "${CSK}.key" > "$infile"
private_type_record $zone 13 "$CSK" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1
setup step3.enable-dnssec.autosign

#
# The zones at zsk-prepub.autosign represent the various steps of a ZSK
# Pre-Publication rollover.
#

# Step 1:
# Introduce the first key. This will immediately be active.
setup step1.zsk-prepub.autosign
TactN="now"
ksktimes="-P ${TactN} -A ${TactN} -P sync ${TactN}"
zsktimes="-P ${TactN} -A ${TactN}"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 3600 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 3600        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TactN -z $O $TactN              "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 2:
# It is time to pre-publish the successor ZSK.
setup step2.zsk-prepub.autosign
# According to RFC 7583:
#
# Tpub(N+1) <= Tact(N) + Lzsk - Ipub
# Ipub = Dprp + TTLkey (+publish-safety)
#
#                 |3|   |4|      |5|  |6|
#                  |     |        |    |
#   Key N          |<-------Lzsk------>|
#                  |     |        |    |
#   Key N+1        |     |<-Ipub->|<-->|
#                  |     |        |    |
#   Key N         Tact
#   Key N+1             Tpub     Trdy Tact
#
#                       Tnow
#
# Lzsk:           30d
# Dprp:           1h
# TTLkey:         1h
# publish-safety: 1d
# Ipub:           26h
#
# Tact(N) = Tnow + Ipub - Lzsk = now + 26h - 30d
#         = now + 26h - 30d = now − 694h
TactN="now-694h"
ksktimes="-P ${TactN} -A ${TactN} -P sync ${TactN}"
zsktimes="-P ${TactN} -A ${TactN}"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 3600 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 3600        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TactN -z $O $TactN              "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 3:
# After the publication interval has passed the DNSKEY of the successor ZSK
# is OMNIPRESENT and the zone can thus be signed with the successor ZSK.
setup step3.zsk-prepub.autosign
# According to RFC 7583:
#
# Tpub(N+1) <= Tact(N) + Lzsk - Ipub
# Tret(N) = Tact(N+1) = Tact(N) + Lzsk
# Trem(N) = Tret(N) + Iret
# Iret = Dsgn + Dprp + TTLsig (+retire-safety)
#
#                 |3|   |4|      |5|  |6|      |7|   |8|
#                  |     |        |    |        |     |
#   Key N          |<-------Lzsk------>|<-Iret->|<--->|
#                  |     |        |    |        |     |
#   Key N+1        |     |<-Ipub->|<-->|<---Lzsk---- - -
#                  |     |        |    |        |     |
#   Key N         Tact                Tret     Tdea  Trem
#   Key N+1             Tpub     Trdy Tact
#
#                                     Tnow
#
# Lzsk:          30d
# Ipub:          26h
# Dsgn:          1w
# Dprp:          1h
# TTLsig:        1d
# retire-safety: 2d
# Iret:          10d1h = 241h
#
# Tact(N)   = Tnow - Lzsk = now - 30d
# Tret(N)   = now
# Trem(N)   = Tnow + Iret = now + 241h
# Tpub(N+1) = Tnow - Ipub = now - 26h
# Tret(N+1) = Tnow + Lzsk = now + 30d
# Trem(N+1) = Tnow + Lzsk + Iret = now + 30d + 241h
#           = now + 961h
TactN="now-30d"
TretN="now"
TremN="now+241h"
TpubN1="now-26h"
TactN1="now"
TretN1="now+30d"
TremN1="now+961h"
ksktimes="-P ${TactN}  -A ${TactN}  -P sync ${TactN}"
zsktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}  -D ${TremN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1} -D ${TremN1}"
KSK=$($KEYGEN  -a ECDSAP256SHA256 -L 3600 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK1=$($KEYGEN -a ECDSAP256SHA256 -L 3600        $zsktimes $zone 2> keygen.out.$zone.2)
ZSK2=$($KEYGEN -a ECDSAP256SHA256 -L 3600        $newtimes $zone 2> keygen.out.$zone.3)
$SETTIME -s -g $O -k $O $TactN  -r $O $TactN  -d $O $TactN "$KSK"  > settime.out.$zone.1 2>&1
$SETTIME -s -g $H -k $O $TactN  -z $O $TactN               "$ZSK1" > settime.out.$zone.2 2>&1
$SETTIME -s -g $O -k $R $TpubN1 -z $H $TpubN1              "$ZSK2" > settime.out.$zone.3 2>&1
# Set key rollover relationship.
key_successor $ZSK1 $ZSK2
# Sign zone.
cat template.db.in "${KSK}.key" "${ZSK1}.key" "${ZSK2}.key" > "$infile"
private_type_record $zone 13 "$KSK"  >> "$infile"
private_type_record $zone 13 "$ZSK1" >> "$infile"
private_type_record $zone 13 "$ZSK2" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 4:
# After the retire interval has passed the predecessor DNSKEY can be
# removed from the zone.
setup step4.zsk-prepub.autosign
# According to RFC 7583:
#
# Tret(N) = Tact(N) + Lzsk
# Tdea(N) = Tret(N) + Iret
#
#                 |3|   |4|      |5|  |6|      |7|   |8|
#                  |     |        |    |        |     |
#   Key N          |<-------Lzsk------>|<-Iret->|<--->|
#                  |     |        |    |        |     |
#   Key N+1        |     |<-Ipub->|<-->|<---Lzsk---- - -
#                  |     |        |    |        |     |
#   Key N         Tact                Tret     Tdea  Trem
#   Key N+1             Tpub     Trdy Tact
#
#                                                    Tnow
#
# Lzsk: 30d
# Ipub: 26h
# Iret: 241h
#
# Tact(N)   = Tnow - Iret - Lzsk
#           = now - 241h - 30d = now - 241h - 720h
#           = now - 961h
# Tret(N)   = Tnow - Iret = now - 241h
# Trem(N)   = Tnow
# Tpub(N+1) = Tnow - Iret - Ipub
#           = now - 241h - 26h
#           = now - 267h
# Tact(N+1) = Tnow - Iret = Tret(N)
# Tret(N+1) = Tnow - Iret + Lzsk
#           = now - 241h + 30d = now - 241h + 720h
#           = now + 479h
# Trem(N+1) = Tnow + Lzsk = now + 30d
TactN="now-961h"
TretN="now-241h"
TremN="now"
TpubN1="now-267h"
TactN1="${TretN}"
TretN1="now+479h"
TremN1="now+30d"
ksktimes="-P ${TactN}  -A ${TactN}  -P sync ${TactN}"
zsktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}  -D ${TremN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1} -D ${TremN1}"
KSK=$($KEYGEN  -a ECDSAP256SHA256 -L 3600 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK1=$($KEYGEN -a ECDSAP256SHA256 -L 3600        $zsktimes $zone 2> keygen.out.$zone.2)
ZSK2=$($KEYGEN -a ECDSAP256SHA256 -L 3600        $newtimes $zone 2> keygen.out.$zone.3)
$SETTIME -s -g $O -k $O $TactN  -r $O $TactN -d $O $TactN "$KSK"  > settime.out.$zone.1 2>&1
$SETTIME -s -g $H -k $O $TactN  -z $U $TretN              "$ZSK1" > settime.out.$zone.2 2>&1
$SETTIME -s -g $O -k $O $TactN1 -z $R $TactN1             "$ZSK2" > settime.out.$zone.3 2>&1
# Set key rollover relationship.
key_successor $ZSK1 $ZSK2
# Sign zone.
cat template.db.in "${KSK}.key" "${ZSK1}.key" "${ZSK2}.key" > "$infile"
$SIGNER -PS -x -s now-2w -e now-1mi -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 5:
# The predecessor DNSKEY is removed long enough that is has become HIDDEN.
setup step5.zsk-prepub.autosign
# Subtract DNSKEY TTL from all the times (1h).
# Tact(N)   = now - 961h - 1h = now - 962h
# Tret(N)   = now - 241h - 1h = now - 242h
# Tdea(N)   = now - 2d - 1h = now - 49h
# Trem(N)   = now - 1h
# Tpub(N+1) = now - 267h - 1h = now - 268h
# Tact(N+1) = Tret(N)
# Tret(N+1) = now + 479h - 1h = now + 478h
# Trem(N+1) = now + 30d - 1h = now + 719h
TactN="now-962h"
TretN="now-242h"
TremN="now-1h"
TdeaN="now-49h"
TpubN1="now-268h"
TactN1="${TretN}"
TretN1="now+478h"
TremN1="now+719h"
ksktimes="-P ${TactN}  -A ${TactN}  -P sync ${TactN}"
zsktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}  -D ${TremN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1} -D ${TremN1}"
KSK=$($KEYGEN  -a ECDSAP256SHA256  -L 3600 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK1=$($KEYGEN -a ECDSAP256SHA256  -L 3600        $zsktimes $zone 2> keygen.out.$zone.2)
ZSK2=$($KEYGEN -a ECDSAP256SHA256  -L 3600        $newtimes $zone 2> keygen.out.$zone.3)
$SETTIME -s -g $O -k $O $TactN  -r $O $TactN -d $O $TactN "$KSK"  > settime.out.$zone.1 2>&1
$SETTIME -s -g $H -k $U $TdeaN  -z $H $TdeaN              "$ZSK1" > settime.out.$zone.2 2>&1
$SETTIME -s -g $O -k $O $TactN1 -z $O $TdeaN              "$ZSK2" > settime.out.$zone.3 2>&1
# Set key rollover relationship.
key_successor $ZSK1 $ZSK2
# Sign zone.
cat template.db.in "${KSK}.key" "${ZSK1}.key" "${ZSK2}.key" > "$infile"
private_type_record $zone 13 "$KSK"  >> "$infile"
private_type_record $zone 13 "$ZSK1" >> "$infile"
private_type_record $zone 13 "$ZSK2" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

#
# The zones at ksk-doubleksk.autosign represent the various steps of a KSK
# Double-KSK rollover.
#

# Step 1:
# Introduce the first key. This will immediately be active.
setup step1.ksk-doubleksk.autosign
TactN="now"
ksktimes="-P ${TactN} -A ${TactN}"
zsktimes="-P ${TactN} -A ${TactN}"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 7200        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O              -k $O $TactN -z $O $TactN "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 2:
# It is time to submit the introduce the new KSK.
setup step2.ksk-doubleksk.autosign
# According to RFC 7583: Tpub(N+1) <= Tact(N) + Lksk - Dreg - IpubC
# Also: IpubC = DprpC + TTLkey (+publish-safety)
# so:   Tact(N) = Tpub(N+1) - Lksk + Dreg + IpubC = now - 60d + (1d3h)
#       now - 1440h + 27h = now - 1413h
TactN="now-1413h"
ksktimes="-P ${TactN} -A ${TactN}"
zsktimes="-P ${TactN} -A ${TactN}"
KSK=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
ZSK=$($KEYGEN -a ECDSAP256SHA256 -L 7200        $zsktimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN "$KSK" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TactN -z $O $TactN              "$ZSK" > settime.out.$zone.2 2>&1
cat template.db.in "${KSK}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 3:
# It is time to submit the DS.
setup step3.ksk-doubleksk.autosign
# According to RFC 7583: Tsbm(N+1) >= Trdy(N+1)
# Also: Tact(N+1) = Tsbm(N+1) + Dreg
# so:   Tact(N) = Tsbm(N+1) + Dreg - Lksk = now + 1d - 60d = now - 59d
# and:  Tret(N) = Tsbm(N+1) + Dreg = now + 1d
# and:  Tpub(N+1) <= Tsbm(N+1) - IpubC = now + 27h
# and:  Tret(N+1) = Tsbm(N+1) + Dreg + Lksk = 1d + 60d
TactN="now-59d"
TretN="now+1d"
TpubN1="now-27h"
TretN1="now+61d"
ksktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
zsktimes="-P ${TactN}  -A ${TactN}"
KSK1=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
KSK2=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $newtimes $zone 2> keygen.out.$zone.2)
ZSK=$($KEYGEN  -a ECDSAP256SHA256 -L 7200        $zsktimes $zone 2> keygen.out.$zone.3)
$SETTIME -s -g $H -k $O $TactN   -r $O $TactN  -d $O $TactN  "$KSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $R $TpubN1  -r $R $TpubN1 -d $H $TpubN1 "$KSK2" > settime.out.$zone.2 2>&1
$SETTIME -s -g $O -k $O $TactN   -z $O $TactN                "$ZSK"  > settime.out.$zone.3 2>&1
# Set key rollover relationship.
key_successor $KSK1 $KSK2
# Sign zone.
cat template.db.in "${KSK1}.key" "${KSK2}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK1" >> "$infile"
private_type_record $zone 13 "$KSK2" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 4:
# The DS should be swapped now.
setup step4.ksk-doubleksk.autosign
# According to RFC 7583: Tdea(N) = Tret(N) + Iret
# Also: Tret(N) = Tsbm(N+1) + Dreg
# Also: Tact(N+1) = Tret(N)
# Also: Iret = DprpP + TTLds (+retire-safety)
# so:   Tact(N) = Tdea(N) - Lksk - Iret = now - 60d - 2d2h = now - 1490h
# and:  Tret(N) = Tdea(N) - Iret = now - 2d2h = 50h
# and:  Tpub(N+1) = Tdea(N) - Iret - Dreg - IpubC = now - 50h - 1d - 1d3h = now - 101h
# and:  Tsbm(N+1) = Tdea(N) - Iret - Dreg = now - 50h - 1d = now - 74h
# and:  Tact(N+1) = Tret(N)
# and:  Tret(N+1) = Tdea(N) + Lksk - Iret = now + 60d - 2d2h = now + 1390h
TactN="now-1490h"
TretN="now-50h"
TpubN1="now-101h"
TsbmN1="now-74h"
TactN1="${TretN}"
TretN1="now+1390h"
ksktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
zsktimes="-P ${TactN}  -A ${TactN}"
KSK1=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
KSK2=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $newtimes $zone 2> keygen.out.$zone.2)
ZSK=$($KEYGEN  -a ECDSAP256SHA256 -L 7200        $zsktimes $zone 2> keygen.out.$zone.3)
$SETTIME -s -g $H -k $O $TactN  -r $O $TactN  -d $U $TsbmN1 "$KSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TsbmN1 -r $O $TsbmN1 -d $R $TsbmN1 "$KSK2" > settime.out.$zone.2 2>&1
$SETTIME -s -g $O -k $O $TactN  -z $O $TactN                "$ZSK"  > settime.out.$zone.3 2>&1
# Set key rollover relationship.
key_successor $KSK1 $KSK2
# Sign zone.
cat template.db.in "${KSK1}.key" "${KSK2}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK1" >> "$infile"
private_type_record $zone 13 "$KSK2" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 5:
# The predecessor DNSKEY is removed long enough that is has become HIDDEN.
setup step5.ksk-doubleksk.autosign
# Subtract DNSKEY TTL from all the times (2h).
TactN="now-1492h"
TretN="now-52h"
TpubN1="now-102h"
TsbmN1="now-75h"
TactN1="${TretN}"
TretN1="now+1388h"
ksktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
zsktimes="-P ${TactN}  -A ${TactN}"
KSK1=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $ksktimes $zone 2> keygen.out.$zone.1)
KSK2=$($KEYGEN -a ECDSAP256SHA256 -L 7200 -f KSK $newtimes $zone 2> keygen.out.$zone.2)
ZSK=$($KEYGEN  -a ECDSAP256SHA256 -L 7200        $zsktimes $zone 2> keygen.out.$zone.3)
$SETTIME -s -g $H -k $U $TretN  -r $U $TretN  -d $H $TretN  "$KSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TactN1 -r $O $TactN1 -d $O $TactN1 "$KSK2" > settime.out.$zone.2 2>&1
$SETTIME -s -g $O -k $O $TactN  -z $O $TactN                "$ZSK"  > settime.out.$zone.3 2>&1
# Set key rollover relationship.
key_successor $KSK1 $KSK2
# Sign zone.
cat template.db.in "${KSK1}.key" "${KSK2}.key" "${ZSK}.key" > "$infile"
private_type_record $zone 13 "$KSK1" >> "$infile"
private_type_record $zone 13 "$KSK2" >> "$infile"
private_type_record $zone 13 "$ZSK" >> "$infile"
$SIGNER -S -x -s now-1h -e now+2w -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

#
# The zones at csk-roll.autosign represent the various steps of a CSK rollover
# (which is essentially a ZSK Pre-Publication / KSK Double-KSK rollover).
#

# Step 1:
# Introduce the first key. This will immediately be active.
setup step1.csk-roll.autosign
TactN="now"
csktimes="-P ${TactN} -A ${TactN}"
CSK=$($KEYGEN -k csk-roll -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN -z $O $TactN "$CSK" > settime.out.$zone.1 2>&1
cat template.db.in "${CSK}.key" > "$infile"
private_type_record $zone 13 "$CSK" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 2:
# It is time to introduce the new CSK.
setup step2.csk-roll.autosign
# According to RFC 7583: ZSK: Tpub(N+1) <= Tact(N) + Lzsk - Ipub
# According to RFC 7583: KSK: Tpub(N+1) <= Tact(N) + Lksk - Dreg - IpubC
# Also: Ipub = Dprp + TTLkey (+publish-safety)
# Also: IpubC = DprpC + TTLkey (+publish-safety)
# Both sums are almost the same, but the KSK case has Dreg in the equation.
# so:   Tact(N) = Tpub(N+1) - Lcsk + Dreg + IpubC = now - 6mo + 1d + 3h =
#       now - 4464h + 24h + 3h = now - 4437h
TactN="now-4437h"
csktimes="-P ${TactN} -A ${TactN}"
CSK=$($KEYGEN -k csk-roll -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN -z $O $TactN "$CSK" > settime.out.$zone.1 2>&1
cat template.db.in "${CSK}.key" > "$infile"
private_type_record $zone 13 "$CSK" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 3:
# It is time to submit the DS and to roll signatures.
setup step3.csk-roll.autosign
# According to RFC 7583: Tsbm(N+1) >= Trdy(N+1)
# Also: Tact(N+1) = Tsbm(N+1) + Dreg
# so:   Tact(N) = Tsbm(N+1) + Dreg - Lksk = now + 1d - 6mo = now - 185d
# and:  Tret(N) = Tsbm(N+1) + Dreg = now + 1d
# and:  Tpub(N+1) <= Tsbm(N+1) - IpubC = now - 3h
# and:  Tret(N+1) = Tsbm(N+1) + Dreg + Lksk = now + 1d + 6mo = now + 187d
TactN="now-185d"
TretN="now+1d"
TpubN1="now-3h"
TretN1="now+187d"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TretN} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $H -k $O $TactN   -r $O $TactN  -d $O $TactN  -z $O $TactN  "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $R $TpubN1  -r $R $TpubN1 -d $H $TpubN1 -z $H $TpubN1 "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 4:
# Some time later all the ZRRSIG records should be from the new CSK, and the
# DS should be swapped.  The ZRRSIG records are all replaced after Iret
# which is Dsgn + Dprp + TTLsig + retire-safety (25d + 1h + 1d + 2h = 26d3h).
# The DS is swapped after Dreg + DprpP + TTLds + retire-safety
# (1d + 1h + 1h + 2h = 1d4h).  In other words, the DS is swapped before all
# zone signatures are replaced.
setup step4.csk-roll.autosign
# According to RFC 7583: Tdea(N) = Tret(N) + Iret
# Also: Iret = 1h + 1h + 2h = 4h
# Also: Tact(N+1) = Tret(N)
# so:   Tact(N) = Tdea(N) - Lksk - Iret = now - 6mo - 4h = now - 4468h
# and:  Tret(N) = Tdea(N) - Iret = now - 4h = now - 4h
# and:  Tpub(N+1) = Tdea(N) - Iret - Dreg - IpubC = now - 4h - 1d - 3h = now - 31h
# and:  Tsbm(N+1) = Tdea(N) - Iret - Dreg = now - 4h - 1d = now - 28h
# and:  Tact(N+1) = Tret(N)
# and:  Tret(N+1) = Tdea(N) + Lksk - Iret = now + 6mo - 4h = now + 4460h
TactN="now-4468h"
TretN="now-4h"
TpubN1="now-31h"
TsbmN1="now-28h"
TactN1="${TretN}"
TretN1="now+4460h"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $H -k $O $TactN  -r $O $TactN  -d $U $TsbmN1 -z $U $TsbmN1 "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TsbmN1 -r $O $TsbmN1 -d $R $TsbmN1 -z $R $TsbmN1 "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 5:
# After the DS is swapped in step 4, also the KRRSIG records can be removed.
# At this time these have all become hidden.
setup step5.csk-roll.autosign
# Subtract DNSKEY TTL plus zone propagation delay from all the times (2h).
TactN="now-4470h"
TretN="now-6h"
TdeaN="now-2h"
TpubN1="now-33h"
TsbmN1="now-30h"
TactN1="${TretN}"
TretN1="now+4458h"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $H -k $O $TactN  -r $U $TdeaN  -d $H $TdeaN  -z $U $TsbmN1 "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TsbmN1 -r $O $TsbmN1 -d $O $TdeaN  -z $R $TsbmN1 "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 6:
# After the retire interval has passed the predecessor DNSKEY can be
# removed from the zone.
setup step6.csk-roll.autosign
# According to RFC 7583: Tdea(N) = Tret(N) + Iret
# Also: Tret(N) = Tact(N) + Lzsk
# Also: Iret = Dsgn + Dprp + TTLsig (+retire-safety)
# so:   Tact(N) = Tdea(N) - Iret - Lzsk = now - 25d1h1d2h - 6mo =
#       now - 26d3h - 6mo = now - 627h - 4464h = now - 5091h
# and:  Tret(N) = Tdea(N) - Iret = now - 627h
# and:  Tpub(N+1) = Tdea(N) - Iret - Ipub = now - 627h - 3h = now - 630h
# and:  Tact(N+1) = Tdea(N) - Iret = Tret(N)
# and:  Tret(N+1) = Tdea(N) - Iret + Lzsk = now - 627h + 6mo = now + 3837h
TactN="now-5091h"
TretN="now-627h"
TdeaN="now-623h"
TpubN1="now-630h"
TsbmN1="now-627h"
TactN1="${TretN}"
TretN1="now+3837h"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -P -g $H -k $O $TactN  -r $H $TdeaN  -d $H $TdeaN  -z $U $TsbmN1 "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -P -g $O -k $O $TsbmN1 -r $O $TsbmN1 -d $O $TdeaN  -z $R $TsbmN1 "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 7:
# Some time later the predecessor DNSKEY enters the HIDDEN state.
setup step7.csk-roll.autosign
# Subtract DNSKEY TTL plus zone propagation delay from all the times (2h).
TactN="now-5093h"
TretN="now-629h"
TdeaN="now-625h"
TpubN1="now-632h"
TsbmN1="now-629h"
TactN1="${TretN}"
TretN1="now+3835h"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $H -k $U now-2h  -r $H $TdeaN  -d $H $TdeaN  -z $H $TsbmN1 "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TsbmN1 -r $O $TsbmN1 -d $O $TdeaN  -z $O $TsbmN1 "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

#
# The zones at csk-roll2.autosign represent the various steps of a CSK rollover
# (which is essentially a ZSK Pre-Publication / KSK Double-KSK rollover).
# This scenario differs from the above one because the zone signatures (ZRRSIG)
# are replaced with the new key sooner than the DS is swapped.
#

# Step 1:
# Introduce the first key. This will immediately be active.
setup step1.csk-roll2.autosign
TactN="now"
csktimes="-P ${TactN} -A ${TactN}"
CSK=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN -z $O $TactN "$CSK" > settime.out.$zone.1 2>&1
cat template.db.in "${CSK}.key" > "$infile"
private_type_record $zone 13 "$CSK" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 2:
# It is time to introduce the new CSK.
setup step2.csk-roll2.autosign
# According to RFC 7583: ZSK: Tpub(N+1) <= Tact(N) + Lzsk - Ipub
# According to RFC 7583: KSK: Tpub(N+1) <= Tact(N) + Lksk - Dreg - IpubC
# Also: Ipub = Dprp + TTLkey (+publish-safety)
# Also: IpubC = DprpC + TTLkey (+publish-safety)
# Both sums are almost the same, but the KSK case has Dreg in the equation.
# so:   Tact(N) = Tpub(N+1) - Lcsk + Dreg + IpubC = now - 6mo + 1w + 3h =
#       now - 4464h + 168h + 3h = now - 4635h
TactN="now-4635h"
csktimes="-P ${TactN} -A ${TactN}"
CSK=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
$SETTIME -s -g $O -k $O $TactN -r $O $TactN -d $O $TactN -z $O $TactN "$CSK" > settime.out.$zone.1 2>&1
cat template.db.in "${CSK}.key" > "$infile"
private_type_record $zone 13 "$CSK" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 3:
# It is time to submit the DS and to roll signatures.
setup step3.csk-roll2.autosign
# According to RFC 7583: Tsbm(N+1) >= Trdy(N+1)
# Also: Tact(N+1) = Tsbm(N+1) + Dreg
# so:   Tact(N) = Tsbm(N+1) + Dreg - Lksk = now + 1w - 6mo = now - 179d
# and:  Tret(N) = Tsbm(N+1) + Dreg = now + 1w
# and:  Tpub(N+1) <= Tsbm(N+1) - IpubC = now - 3h
# and:  Tret(N+1) = Tsbm(N+1) + Dreg + Lksk = now + 1w + 6mo = now + 193d
TactN="now-179d"
TretN="now+1w"
TpubN1="now-3h"
TretN1="now+193d"
csktimes="-P ${TactN}  -A ${TactN} -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TretN} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $H -k $O $TactN   -r $O $TactN  -d $O $TactN  -z $O $TactN  "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $R $TpubN1  -r $R $TpubN1 -d $H $TpubN1 -z $H $TpubN1 "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 4:
# Some time later all the ZRRSIG records should be from the new CSK, and the
# DS should be swapped.  The ZRRSIG records are all replaced after Iret
# which is Dsgn + Dprp + TTLsig + retire-safety (12h + 1h + 1d + 2h = 38h).
# The DS is swapped after Dreg + DprpP + TTLds + retire-safety
# (1w + 1h + 1h + 1h = 1w3h).  In other words, the zone signatures are
# replaced before the DS is swapped.
setup step4.csk-roll2.autosign
# According to RFC 7583: Tdea(N) = Tret(N) + Iret
# Also: Tret(N) = Tact(N) + Lzsk
# Also: Iret = Dsgn + Dprp + TTLsig (+retire-safety)
# so:   Tact(N) = Tdea(N) - Iret - Lzsk = now - 38h - 6mo = now - 4502h
# and:  Tret(N) = Tdea(N) - Iret = now - 38h
# and:  Tpub(N+1) = Tdea(N) - Iret - Ipub = now - 41h
# and:  Tact(N+1) = Tdea(N) - Iret = Tret(N)
# and:  Tret(N+1) = Tdea(N) - Iret + Lzsk = now - 38h + 6mo = now + 4426h
TactN="now-4502h"
TretN="now-38h"
TpubN1="now-41h"
TactN1="${TretN}"
TretN1="now+4426"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $H -k $O $TactN -r $O $TactN  -d $U $TretN -z $U $TretN "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TretN -r $O $TretN  -d $R $TretN -z $R $TretN "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 5:
# Some time later the DS can be swapped and the old DNSKEY can be removed from
# the zone.
setup step5.csk-roll2.autosign
# Subtract Dreg + Iret (174h).
TactN="now-4676h"
TretN="now-212h"
TpubN1="now-215h"
TactN1="${TretN}"
TretN1="now+4252h"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -g $H -k $O $TactN -r $O $TactN -d $U $TretN -z $H $TretN "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -g $O -k $O $TretN -r $O $TretN -d $R $TretN -z $O $TretN "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1

# Step 6:
# Some time later the predecessor DNSKEY enters the HIDDEN state.
setup step6.csk-roll2.autosign
# Subtract DNSKEY TTL plus zone propagation delay (2h).
TactN="now-4678h"
TretN="now-214h"
TdeaN="now-2h"
TpubN1="now-217h"
TactN1="${TretN}"
TretN1="now+4250h"
csktimes="-P ${TactN}  -A ${TactN}  -I ${TretN}"
newtimes="-P ${TpubN1} -A ${TactN1} -I ${TretN1}"
CSK1=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $csktimes $zone 2> keygen.out.$zone.1)
CSK2=$($KEYGEN -k csk-roll2 -l policies/autosign.conf $newtimes $zone 2> keygen.out.$zone.2)
$SETTIME -s -P $TactN  -A $TactN  -I $TretN  -g $H -k $U $TdeaN -r $U $TdeaN -d $H $TretN -z $H $TretN "$CSK1" > settime.out.$zone.1 2>&1
$SETTIME -s -P $TpubN1 -A $TactN1 -I $TretN1 -g $O -k $O $TretN -r $O $TretN -d $O $TretN -z $O $TretN "$CSK2" > settime.out.$zone.2 2>&1
# Set key rollover relationship.
key_successor $CSK1 $CSK2
# Sign zone.
cat template.db.in "${CSK1}.key" "${CSK2}.key" > "$infile"
private_type_record $zone 13 "$CSK1" >> "$infile"
private_type_record $zone 13 "$CSK2" >> "$infile"
$SIGNER -S -z -x -s now-1h -e now+30d -o $zone -O full -f $zonefile $infile > signer.out.$zone.1 2>&1
