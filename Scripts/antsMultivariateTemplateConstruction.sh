#!/bin/bash

VERSION="0.0.15 test"

# trap keyboard interrupt (control-c)
trap control_c SIGINT

function setPath {
    cat <<SETPATH

--------------------------------------------------------------------------------------
Error locating ANTS
--------------------------------------------------------------------------------------
It seems that the ANTSPATH environment variable is not set. Please add the ANTSPATH
variable. This can be achieved by editing the .bash_profile in the home directory.
Add:

ANTSPATH=/home/yourname/bin/ants/

Or the correct location of the ANTS binaries.

Alternatively, edit this script ( `basename $0` ) to set up this parameter correctly.

SETPATH
    exit 1
}

# Uncomment the line below in case you have not set the ANTSPATH variable in your environment.
# export ANTSPATH=${ANTSPATH:="$HOME/bin/ants/"} # EDIT THIS

#ANTSPATH=YOURANTSPATH
if [ ${#ANTSPATH} -le 3 ];
    then
    setPath >&2
fi

if [ ! -s ${ANTSPATH}/ANTS ];
    then
    echo "ANTS program can't be found. Please (re)define \$ANTSPATH in your environment."
    exit
fi

# Test availability of helper scripts.
# No need to test this more than once. Can reside outside of the main loop.
ANTS=${ANTSPATH}ANTS
WARP=${ANTSPATH}/WarpImageMultiTransform
N4=${ANTSPATH}N4BiasFieldCorrection
PEXEC=${ANTSPATH}ANTSpexec.sh
SGE=${ANTSPATH}waitForSGEQJobs.pl
PBS=${ANTSPATH}waitForPBSQJobs.pl
XGRID=${ANTSPATH}waitForXGridJobs.pl

fle_error=0
for FLE in $N4 $PEXEC $SGE $XGRID $PBS
  do
  if [ ! -x $FLE ];
      then
      echo
      echo "--------------------------------------------------------------------------------------"
      echo " FILE $FLE DOES NOT EXIST -- OR -- IS NOT EXECUTABLE !!! $0 will terminate."
      echo "--------------------------------------------------------------------------------------"
      echo " if the file is not executable, please change its permissions. "
      fle_error=1
  fi
done

if [ $fle_error = 1 ];
    then
    echo "missing helper script"
    exit 1
fi


#assuming .nii.gz as default file type. This is the case for ANTS 1.7 and up

function Usage {
    cat <<USAGE

Usage:

`basename $0` -d ImageDimension -o OUTPREFIX <other options> <images>

Compulsory arguments (minimal command line requires SGE cluster, otherwise use -c & -j options):

     -d:  ImageDimension: 2 or 3 (for 2 or 3 dimensional registration of single volume)
	  ImageDimension: 4 (for template generation of time-series data)

     -o:  OUTPREFIX; A prefix that is prepended to all output files.

<images>  List of images in the current directory, eg *_t1.nii.gz. Should be at the end
          of the command.  Optionally, one can specify a .csv or .txt file where each
          line is the location of the input image.  One can also specify more than
          one file for each image for multi-modal template construction (e.g. t1 and t2).
          For the multi-modal case, the templates will be consecutively numbered (e.g.
          ${OUTPUTPREFIX}template0.nii.gz, ${OUTPUTPREFIX}template1.nii.gz, ...).

NB: All images to be added to the template should be in the same directory, and this script
should be invoked from that directory.

Optional arguments:

     -c:  Control for parallel computation (default 1) -- 0 == run serially,  1 == SGE qsub,
	         2 == use PEXEC (localhost), 3 == Apple XGrid, 4 == PBS qsub

     -g:  Gradient step size (default 0.25) -- smaller in magnitude results in more cautious steps

     -i:  Iteration limit (default 4) -- iterations of the template construction (Iteration limit)*NumImages registrations.

     -j:  Number of cpu cores to use (default 2; -- requires "-c 2")

     -k:  Number of modalities used to construct the template (default 1)

     -w:  Modality weights used in the similarity metric (default = 1) --- specified as e.g. 1x0.5x0.75

     -m:  Max-iterations in each registration

     -n:  N4BiasFieldCorrection of moving image (default 1) -- 0 == off, 1 == on

     -p:  Commands to prepend to job scripts (e.g., change into appropriate directory, set paths, etc)

     -r:  Do rigid-body registration of inputs before creating template (default 0) -- 0 == off 1 == on. Only useful when
          you do not have an initial template

     -s:  Type of similarity metric used for registration.

     -t:  Type of transformation model used for registration.

     -x:  XGrid arguments (e.g., -x "-p password -h controlhost")

     -z:  Use this this volume as the target of all inputs. When not used, the script
          will create an unbiased starting point by averaging all inputs. Use the full path!

Example:

`basename $0` -d 3 -m 30x50x20 -t GR -s CC -c 1 -o MY -z InitialTemplate.nii.gz  *RF*T1x.nii.gz

- In this example 30x50x20 iterations per registration are used for template creation (that is the default)
- Greedy-SyN and CC are the metrics to guide the mapping.
- Output is prepended with MY and the initial template is InitialTemplate.nii.gz (optional).
- The -c option is set to 1, which will result in using the Sun Grid Engine (SGE) to distribute the computation.
- if you do not have SGE, read the help for multi-core computation on the local machine, or Apple X-grid options.

--------------------------------------------------------------------------------------
ANTS was created by:
--------------------------------------------------------------------------------------
Brian B. Avants, Nick Tustison and Gang Song
Penn Image Computing And Science Laboratory
University of Pennsylvania

Please reference http://www.ncbi.nlm.nih.gov/pubmed/20851191 when employing this script
in your studies. A reproducible evaluation of ANTs similarity metric performance in
brain image registration:

* Avants BB, Tustison NJ, Song G, Cook PA, Klein A, Gee JC. Neuroimage, 2011.

Also see http://www.ncbi.nlm.nih.gov/pubmed/19818860 for more details.

The script has been updated and improved since this publication.

--------------------------------------------------------------------------------------
script adapted by N.M. van Strien, http://www.mri-tutorial.com | NTNU MR-Center
multivariate template adaption by Nick Tustison
--------------------------------------------------------------------------------------
Apple XGrid support by Craig Stark
--------------------------------------------------------------------------------------

USAGE
    exit 1
}

function Help {
    cat <<HELP

`basename $0` will make a template out of the input files using an elastic
or diffeomorphic transformation. This script builds a template iteratively from the input
images and uses Sun Grid Engine (SGE) or multiple cpu cores on the localhost (min 2) to
parallelize the registration of each subject to the template.

Usage:

`basename $0` -d ImageDimension -o OUTPREFIX <other options> <images>

Example Case:

 bash `basename $0` -d 3 -m 30x50x20 -t GR  -s CC -c 1 -o MY -z InitialTemplate.nii.gz  *RF*T1x.nii.gz

 - In this case you use 30x50x20 iterations per registration
 - 4 iterations over template creation (that is the default)
 - With Greedy-SyN and CC metrics to guide the mapping.
 - Output is prepended with MY and the initial template is InitialTemplate.nii.gz (optional).
 - The -c option is set to 1 which will try to use SGE to distribute the computation.
 - If you do not have SGE, use -c 0 or -c 2 combined with -j.

 - Continue reading this help file if things are not yet clear.

Compulsory arguments (minimal command line requires SGE cluster, otherwise use -c & -j options):

     -d:  ImageDimension: 2 or 3 (for 2 or 3 dimensional registration of single volume)
	  ImageDimension: 4 (for template generation of time-series data)

     -o:  OUTPREFIX; A prefix that is prepended to all output files.

<images>  List of images in the current directory, eg *_t1.nii.gz. Should be at the end
          of the command.  Optionally, one can specify a .csv or .txt file where each
          line is the location of the input image.  One can also specify more than
          one file for each image for multi-modal template construction (e.g. t1 and t2).
          For the multi-modal case, the templates will be consecutively numbered (e.g.
          ${OUTPUTPREFIX}template0.nii.gz, ${OUTPUTPREFIX}template1.nii.gz, ...).

NB: All files to be added to the template should be in the same directory.

Optional arguments:

     -c:  Control for parallel computation (default 1) -- 0 == run serially,  1 == SGE qsub,
	         2 == use PEXEC (localhost), 3 == Apple XGrid, 4 == PBS qsub

     -g:  Gradient step size; smaller in magnitude results in more cautious steps (default 0.25)

     -i:  Iteration limit (default = 4) for template construction. requires 4*NumImages registrations.

     -j:  Number of cpu cores to use (default: 2; --- set -c option to 2 to use this.

     -k:  Number of modalities used to construct the template.

     -w:  Modality weights used in the similarity metric (default = 1) --- specified as e.g. 1x0.5x0.75

	  The optimal number of cpu cores to use for template generation depends on the availability of cores, the amount of
	  free working memory (RAM) and the resolution of the data. High resolution datasets typically require more RAM during
	  processing. Running out of RAM during a calculation will slow down all processing on your computer.

     -m:  Max-iterations

          Max-Iterations in form: JxKxL where
	     J = max iterations at coarsest resolution (here, reduce by power of 2^2)
	     K = middle resolution iterations (here,reduce by power of 2)
	     L = fine resolution iterations (here, full resolution) !!this level takes much
                 more time per iteration!!

	  Adding an extra value before JxKxL (i.e. resulting in IxJxKxL) would add another
	  iteration level.

     -n:  N4BiasFieldCorrection of moving image ( 0 = off; 1 = on (default) )

     -p:  Commands to prepend to job scripts (e.g., change into appropriate directory, set paths, etc)

     -r:  Do rigid-body registration of inputs before creating template (default 0) -- 0 == off 1 == on. Only useful when
          you do not have an initial template

          In case a template is specified (-z option), all inputs are registered to that template. If
          no template is specified, the inputs will be registered to the averaged input.

     -s:  Type of similarity metric used for registration.

	     For intramodal image registration, use:
	     CC = cross-correlation
	     MI = mutual information
	     PR = probability mapping (default)
	     MSQ = mean square difference (Demons-like)
	     SSD = sum of squared differences

	     For intermodal image registration, use:
	     MI = mutual information
	     PR = probability mapping (default)

     -t:  Type of transformation model used for registration.

	     For rigid image registration, use:
	     RI = Purely rigid
	     RA = Affine rigid

	     For elastic image registration, use:
	     EL = elastic transformation model (less deformation possible)

	     For diffeomorphic image registration, use:
	     SY = SyN with time (default) with arbitrary number of time points in time discretization
	     S2 = SyN with time optimized specifically for 2 time points in the time discretization
	     GR = Greedy SyN
	     EX = Exponential
             DD = Diffeomorphic Demons style exponential mapping

     -x:  XGrid arguments (e.g., -x "-p password -h controlhost")

     -z:  Use this this volume as the target of all inputs. When not used, the script
          will create an unbiased starting point by averaging all inputs. Use the full path!

Requirements:

This scripts relies on the following scripts in your $ANTSPATH directory. The script
will terminate prematurely if these files are not present or are not executable.
- antsIntroduction.sh
- pexec.sh
- waitForSGEQJobs.pl (only for use with Sun Grid Engine)
- waitForPBSQJobs.pl  (only for use with Portable Batch System)
- ANTSpexec.sh (only for use with localhost parallel execution)
- waitForXGridJobs.pl (only for use with Apple XGrid)

--------------------------------------------------------------------------------------
Get the latest ANTS version at:
--------------------------------------------------------------------------------------
http://sourceforge.net/projects/advants/

--------------------------------------------------------------------------------------
Read the ANTS documentation at:
--------------------------------------------------------------------------------------
http://picsl.upenn.edu/ANTS/

--------------------------------------------------------------------------------------
ANTS was created by:
--------------------------------------------------------------------------------------
Brian B. Avants, Nick Tustison and Gang Song
Penn Image Computing And Science Laboratory
University of Pennsylvania

Please reference http://www.ncbi.nlm.nih.gov/pubmed/20851191 when employing this script
in your studies. A reproducible evaluation of ANTs similarity metric performance in
brain image registration:

* Avants BB, Tustison NJ, Song G, Cook PA, Klein A, Gee JC. Neuroimage, 2011.

Also see http://www.ncbi.nlm.nih.gov/pubmed/19818860 for more details.

The script has been updated and improved since this publication.

--------------------------------------------------------------------------------------
script adapted by N.M. van Strien, http://www.mri-tutorial.com | NTNU MR-Center
multivariate template adaption by Nick Tustison
--------------------------------------------------------------------------------------
Apple XGrid support by Craig Stark
--------------------------------------------------------------------------------------

HELP
    exit 1
}

function reportMappingParameters {
    cat <<REPORTMAPPINGPARAMETERS

--------------------------------------------------------------------------------------
 Mapping parameters
--------------------------------------------------------------------------------------
 ANTSPATH is $ANTSPATH

 Dimensionality:			$DIM
 N4BiasFieldCorrection:			$N4CORRECT
 Similarity Metric:			$METRICTYPE
 Transformation:			$TRANSFORMATIONTYPE
 Regularization:			$REGULARIZATION
 MaxIterations:				$MAXITERATIONS
 Number Of MultiResolution Levels:	$NUMLEVELS
 OutputName prefix:			$OUTPUTNAME
 Template:  				$TEMPLATENAME
 Template Update Steps:			$ITERATIONLIMIT
 Template population:	   		$IMAGESETVARIABLE
 Number of Modalities:     $NUMBEROFMODALITIES
 Madality weights:         $MODALITYWEIGHTSTRING
--------------------------------------------------------------------------------------
REPORTMAPPINGPARAMETERS
}

function shapeupdatetotemplate() {

    # local declaration of values
    dim=$1
    template=$2
    templatename=$3
    outputname=$4
    gradientstep=-$5
    whichtemplate=$6

# debug only
# echo $dim
# echo ${template}
# echo ${templatename}
# echo ${outputname}
# echo ${outputname}*WarpedToTemplate.nii*
# echo ${gradientstep}

# We find the average warp to the template and apply its inverse to the template image
# This keeps the template shape stable over multiple iterations of template building

    echo
    echo "--------------------------------------------------------------------------------------"
    echo " shapeupdatetotemplate---voxel-wise averaging of the warped images to the current template"
    echo "   ${ANTSPATH}AverageImages $dim ${template} 1 ${templatename}${whichtemplate}*WarpedToTemplate.nii.gz    "
    echo "--------------------------------------------------------------------------------------"
	   ${ANTSPATH}AverageImages $dim ${template} 1 ${templatename}${whichtemplate}*WarpedToTemplate.nii.gz

    if [ $whichtemplate -eq 0 ] ;
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " shapeupdatetotemplate---voxel-wise averaging of the inverse warp fields (from subject to template)"
        echo	"   ${ANTSPATH}AverageImages $dim ${templatename}${whichtemplate}warp.nii.gz 0 `ls ${outputname}*Warp.nii.gz | grep -v "InverseWarp"`"
        echo "--------------------------------------------------------------------------------------"

        ${ANTSPATH}AverageImages $dim ${templatename}${whichtemplate}warp.nii.gz 0 `ls ${outputname}*Warp.nii.gz | grep -v "InverseWarp"`

        echo
        echo "--------------------------------------------------------------------------------------"
        echo " shapeupdatetotemplate---scale the averaged inverse warp field by the gradient step"
        echo "   ${ANTSPATH}MultiplyImages $dim ${templatename}${whichtemplate}warp.nii.gz ${gradientstep} ${templatename}${whichtemplate}warp.nii.gz"
        echo "--------------------------------------------------------------------------------------"

        ${ANTSPATH}MultiplyImages $dim ${templatename}${whichtemplate}warp.nii.gz ${gradientstep} ${templatename}${whichtemplate}warp.nii.gz

        then
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " shapeupdatetotemplate---average the affine transforms (template <-> subject)"
        echo "                      ---transform the inverse field by the resulting average affine transform"
        echo "   ${ANTSPATH}AverageAffineTransform ${dim} ${templatename}0Affine.txt ${outputname}*Affine.txt"
        echo "   ${ANTSPATH}WarpImageMultiTransform ${dim} ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz -i  ${templatename}0Affine.txt -R ${template}"
        echo "--------------------------------------------------------------------------------------"

        ${ANTSPATH}AverageAffineTransform ${dim} ${templatename}0Affine.txt ${outputname}*Affine.txt
        ${ANTSPATH}WarpImageMultiTransform ${dim} ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz -i  ${templatename}0Affine.txt -R ${template}

        ${ANTSPATH}MeasureMinMaxMean ${dim} ${templatename}0warp.nii.gz ${templatename}warplog.txt 1
    fi

    echo "--------------------------------------------------------------------------------------"
    echo " shapeupdatetotemplate---warp each template by the resulting transforms"
    echo "   ${ANTSPATH}WarpImageMultiTransform ${dim} ${template} ${template} -i ${templatename}0Affine.txt ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz -R ${template}"
    echo "--------------------------------------------------------------------------------------"
    ${ANTSPATH}WarpImageMultiTransform ${dim} ${template} ${template} -i ${templatename}0Affine.txt ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz ${templatename}0warp.nii.gz -R ${template}
}

function jobfnamepadding {

    outdir=`dirname ${TEMPLATES[0]}`
    if [ ${#outdir} -eq 0 ]
        then
        outdir=`pwd`
    fi

    files=`ls ${outdir}/job*.sh`
    BASENAME1=`echo $files[1] | cut -d 'b' -f 1`

    for file in ${files}
      do

      if [ "${#file}" -eq "9" ]
	  then
	  BASENAME2=`echo $file | cut -d 'b' -f 2 `
	  mv "$file" "${BASENAME1}b_000${BASENAME2}"

      elif [ "${#file}" -eq "10" ]
	  then
	  BASENAME2=`echo $file | cut -d 'b' -f 2 `
	  mv "$file" "${BASENAME1}b_00${BASENAME2}"

      elif [ "${#file}" -eq "11" ]
	  then
	  BASENAME2=`echo $file | cut -d 'b' -f 2 `
	  mv "$file" "${BASENAME1}b_0${BASENAME2}"
      fi
    done
}

function setCurrentImageSet() {

WHICHMODALITY=$1

CURRENTIMAGESET=()
COUNT=0

for (( g = $WHICHMODALITY; g < ${#IMAGESETARRAY[@]}; g+=$NUMBEROFMODALITIES ))
    do
    CURRENTIMAGESET[$COUNT]=${IMAGESETARRAY[$g]}
    (( COUNT++ ))
done
}

cleanup()
# example cleanup function
{

  cd ${currentdir}/

  echo -en "\n*** Performing cleanup, please wait ***\n"

# 1st attempt to kill all remaining processes
# put all related processes in array
  runningANTSpids=( `ps -C ANTS -C N4BiasFieldCorrection -C ImageMath| awk '{ printf "%s\n", $1 ; }'` )

# debug only
  #echo list 1: ${runningANTSpids[@]}

# kill these processes, skip the first since it is text and not a PID
  for ((i = 1; i < ${#runningANTSpids[@]} ; i++))
  do
  echo "killing:  ${runningANTSpids[${i}]}"
  kill ${runningANTSpids[${i}]}
  done

  return $?
}

control_c()
# run if user hits control-c
{
  echo -en "\n*** User pressed CTRL + C ***\n"
  cleanup
  exit $?
  echo -en "\n*** Script cancelled by user ***\n"
}

#initializing variables with global scope
time_start=`date +%s`
currentdir=`pwd`
nargs=$#

MAXITERATIONS=30x90x20
LABELIMAGE=0 # initialize optional parameter
METRICTYPE=CC # initialize optional parameter
TRANSFORMATIONTYPE="GR" # initialize optional parameter
if [[ $dim == 4 ]]; then
  # we use a more constrained regularization for 4D mapping b/c we expect deformations to be relatively small and local
  TRANSFORMATIONTYPE="GR_Constrained"
fi
NUMBEROFMODALITIES=1
MODALITYWEIGHTSTRING=""
N4CORRECT=1 # initialize optional parameter
DOQSUB=1 # By default, antsMultivariateTemplateConstruction tries to do things in parallel
GRADIENTSTEP=0.25 # Gradient step size, smaller in magnitude means more smaller (more cautious) steps
ITERATIONLIMIT=4
CORES=2
TDIM=0
RIGID=0
RIGIDTYPE="" # set to an empty string to use affine initialization
range=0
REGTEMPLATES=()
TEMPLATES=()
CURRENTIMAGESET=()
XGRIDOPTS=""
SCRIPTPREPEND=""
# System specific queue options, eg "-q name" to submit to a specific queue
# It can be set to an empty string if you do not need any special cluster options
QSUBOPTS="" # EDIT THIS
OUTPUTNAME=antsBTP

##Getting system info from linux can be done with these variables.
# RAM=`cat /proc/meminfo | sed -n -e '/MemTotal/p' | awk '{ printf "%s %s\n", $2, $3 ; }' | cut -d " " -f 1`
# RAMfree=`cat /proc/meminfo | sed -n -e '/MemFree/p' | awk '{ printf "%s %s\n", $2, $3 ; }' | cut -d " " -f 1`
# cpu_free_ram=$((${RAMfree}/${cpu_count}))

if [ ${OSTYPE:0:6} == 'darwin' ]
	then
	cpu_count=`sysctl -n hw.physicalcpu`
else
	cpu_count=`cat /proc/cpuinfo | grep processor | wc -l`
fi

# Provide output for Help
if [ "$1" == "-h" ]
    then
    Help >&2

fi

# reading command line arguments
while getopts "c:d:g:h:i:j:k:m:n:o:p:s:r:t:w:x:z:" OPT
  do
  case $OPT in
      h) #help
	  echo "$USAGE"
	  exit 0
	  ;;
      c) #use SGE cluster
	  DOQSUB=$OPTARG
	  if [[ ${#DOQSUB} -gt 2 ]]; then
	      echo " DOQSUB must be an integer value (0=serial, 1=SGE qsub, 2=try pexec, 3=XGrid, 4=PBS qsub ) you passed  -c $DOQSUB "
	      exit 1
	  fi
	  ;;
      d) #dimensions
	  DIM=$OPTARG
	  if [[ ${DIM} -eq 4 ]]; then
	      DIM=3
	      TDIM=4
	  fi
	  ;;
      g) #gradient stepsize (default = 0.25)
	  GRADIENTSTEP=$OPTARG
	  ;;
      i) #iteration limit (default = 3)
	  ITERATIONLIMIT=$OPTARG
	  ;;
      j) #number of cpu cores to use (default = 2)
	  CORES=$OPTARG
	  ;;
      k) #number of modalities used to construct the template (default = 1)
	  NUMBEROFMODALITIES=$OPTARG
	  ;;
      w) #modality weights (default = 1)
	  MODALITYWEIGHTSTRING=$OPTARG
	  ;;
      m) #max iterations other than default
	  MAXITERATIONS=$OPTARG
	  ;;
      n) #apply bias field correction
	  N4CORRECT=$OPTARG
	  ;;
      o) #output name prefix
	  OUTPUTNAME=$OPTARG
	  TEMPLATENAME=${OUTPUTNAME}template
	  ;;
      p) #Script prepend
	  SCRIPTPREPEND=$OPTARG
	  ;;
      s) #similarity model
	  METRICTYPE=$OPTARG
	  ;;
      r) #start with rigid-body registration
	  RIGID=$OPTARG
	  ;;
      t) #transformation model
	  TRANSFORMATIONTYPE=$OPTARG
	  ;;
      x) #initialization template
	  XGRIDOPTS=$XGRIDOPTS
	  ;;
      z) #initialization template
	  REGTEMPLATES[${#REGTEMPLATES[@]}]=$OPTARG
	  ;;
      \?) # getopts issues an error message
      echo "$USAGE" >&2
      exit 1
      ;;
  esac
done

# Provide different output for Usage and Help
if [ ${TDIM} -eq 4 ] && [ $nargs -lt 5 ]
    then
    Usage >&2
elif [ ${TDIM} -eq 4 ] && [ $nargs -eq 5 ]
    then
    echo ""
    # This option is required to run 4D template creation on SGE with a minimal command line
elif [ $nargs -lt 6 ]
    then
    Usage >&2
fi

if [[ $DOQSUB -eq 1 || $DOQSUB -eq 4 ]];
    then
    qq=`which  qsub`
    if [  ${#qq} -lt 1 ];
        then
        echo "do you have qsub?  if not, then choose another c option ... if so, then check where the qsub alias points ..."
        exit
    fi
fi

for (( i = 0; i < $NUMBEROFMODALITIES; i++ ))
    do
	   TEMPLATES[$i]=${TEMPLATENAME}${i}.nii.gz
done

if [ ! -n "$MODALITYWEIGHTSTRING" ];
    then
    for (( $i = 0; $i < $NUMBEROFMODALITIES; $i++ ))
        do
        MODALITYWEIGHTS[$i]=1
    done
else
    MODALITYWEIGHTS=(`echo $MODALITYWEIGHTSTRING | tr 'x' "\n"`)
    if [ ${#MODALITYWEIGHTS[@]} -ne $NUMBEROFMODALITIES ];
        then
        echo "The number of weights (specified e.g. -w 1x1x1) does not match the number of specified modalities (see -k option)";
        exit
    fi
fi

# Creating the file list of images to make a template from.
# Shiftsize is calculated because a variable amount of arguments can be used on the command line.
# The shiftsize variable will give the correct number of arguments to skip. Issuing shift $shiftsize will
# result in skipping that number of arguments on the command line, so that only the input images remain.
shiftsize=$(($OPTIND - 1))
shift $shiftsize
# The invocation of $* will now read all remaining arguments into the variable IMAGESETVARIABLE
IMAGESETVARIABLE=$*
NINFILES=$(($nargs - $shiftsize))
IMAGESETARRAY=()

# FSL not needed anymore, all dependent on ImageMath
# #test if FSL is available in case of 4D, exit if not
# if [  ${TDIM} -eq 4 ] && [  ${#FSLDIR} -le 0 ]
#     then
#     setFSLPath >&2
# fi

if [ ${NINFILES} -eq 0 ]
    then
    echo "Please provide at least 2 filenames for the template."
    echo "Use `basename $0` -h for help"
    exit 1
elif [[ ${NINFILES} -eq 1 ]]
    then
    extension=`echo ${IMAGESETVARIABLE#*.}`
    if [[ $extension = 'csv' ]] || [[ $extension = 'txt' ]]
        then
        IMAGESFILE=$IMAGESETVARIABLE
        IMAGECOUNT=0
        while read line
            do
            files=(`echo $line | tr ',' ' '`)
            if [ ${#files[@]} -ne $NUMBEROFMODALITIES ]
                then
                echo "The number of files in the csv file does not match the specified number of modalities."
                echo "See the -k option."
                exit 1
            fi
            for (( i = 0; i < ${#files[@]}; i++ ));
                do
                IMAGESETARRAY[$IMAGECOUNT]=${files[$i]}
                ((IMAGECOUNT++))
            done
         done < $IMAGESFILE
    else
        range=`${ANTSPATH}ImageMath $TDIM abs nvols ${IMAGESETVARIABLE} | tail -1 | cut -d "," -f 4 | cut -d " " -f 2 | cut -d "]" -f 1 `
        if [ ${range} -eq 1 ] && [ ${TDIM} -ne 4 ]
            then
            echo "Please provide at least 2 filenames for the template."
            echo "Use `basename $0` -h for help"
            exit 1
        elif [ ${range} -gt 1 ] && [ ${TDIM} -ne 4 ]
            then
            echo "This is a multivolume file. Use -d 4"
            echo "Use `basename $0` -h for help"
            exit 1
        elif [ ${range} -gt 1 ] && [ ${TDIM} -eq 4 ]
            then
            echo
            echo "--------------------------------------------------------------------------------------"
            echo " Creating template of 4D input. "
            echo "--------------------------------------------------------------------------------------"

             #splitting volume
             #setting up working dirs
             tmpdir=${currentdir}/tmp_${RANDOM}_${RANDOM}_${RANDOM}_$$
             (umask 077 && mkdir ${tmpdir}) || {
                 echo "Could not create temporary directory! Exiting." 1>&2
                 exit 1
                 }

             mkdir ${tmpdir}/selection

             #split the 4D file into 3D elements
             cp ${IMAGESETVARIABLE} ${tmpdir}/
             cd ${tmpdir}/
             # ${ANTSPATH}ImageMath $TDIM vol0.nii.gz TimeSeriesSubset ${IMAGESETVARIABLE} ${range}
             #	rm -f ${IMAGESETVARIABLE}

             # selecting 16 volumes randomly from the timeseries for averaging, placing them in tmp/selection folder.
             # the script will automatically divide timeseries into $total_volumes/16 bins from wich to take the random volumes;
             # if there are more than 32 volumes in the time-series (in case they are smaller

             nfmribins=16
            if [ ${range} -gt 31  ];
                then
                BINSIZE=$((${range} / ${nfmribins}))
                j=1 # initialize counter j
                for ((i = 0; i < ${nfmribins}; i++))
                    do
                    FLOOR=$((${i} * ${BINSIZE}))
                    BINrange=$((${j} * ${BINSIZE}))
                    # Retrieve random number between two limits.
                    number=0   #initialize
                    while [ "$number" -le $FLOOR ]
                        do
                        number=$RANDOM
                        if [ $i -lt 15 ]
                            then
                            let "number %= $BINrange"  # Scales $number down within $range.
                        elif [ $i -eq 15 ]
                            then
                            let "number %= $range"  # Scales $number down within $range.
                        fi
                    done
                    #debug only
                    echo
                    echo "Random number between $FLOOR and $BINrange ---  $number"
                    #			echo "Random number between $FLOOR and $range ---  $number"

                    if [ ${number} -lt 10 ]
                        then
                        ${ANTSPATH}ImageMath $TDIM selection/vol000${number}.nii.gz ExtractSlice ${IMAGESETVARIABLE} ${number}
                        #					cp vol000${number}.nii.gz selection/
                    elif [ ${number} -ge 10 ] && [ ${number} -lt 100 ]
                        then
                        ${ANTSPATH}ImageMath $TDIM selection/vol00${number}.nii.gz ExtractSlice ${IMAGESETVARIABLE} ${number}
                        #					cp vol00${number}.nii.gz selection/
                    elif [ ${number} -ge 100 ] && [ ${number} -lt 1000 ]
                        then
                        ${ANTSPATH}ImageMath $TDIM selection/vol0${number}.nii.gz ExtractSlice ${IMAGESETVARIABLE} ${number}
                        #					cp vol0${number}.nii.gz selection/
                    fi
                    let j++
                done
            fi
        elif [ ${range} -gt ${nfmribins}  ] && [ ${range} -lt 32  ]
            then
            for ((i = 0; i < ${nfmribins} ; i++))
                do
                number=$RANDOM
                let "number %= $range"
                if [ ${number} -lt 10 ]
                    then
                    ${ANTSPATH}ImageMath $TDIM selection/vol0.nii.gz ExtractSlice ${IMAGESETVARIABLE} ${number}
                    #					cp vol000${number}.nii.gz selection/
                elif [ ${number} -ge 10 ] && [ ${number} -lt 100 ]
                    then
                    ${ANTSPATH}ImageMath $TDIM selection/vol0.nii.gz ExtractSlice ${IMAGESETVARIABLE} ${number}
                    #					cp vol00${number}.nii.gz selection/
                fi
            done
        elif [ ${range} -le ${nfmribins}  ]
            then
            ${ANTSPATH}ImageMath selection/$TDIM vol0.nii.gz TimeSeriesSubset ${IMAGESETVARIABLE} ${range}
            #		cp *.nii.gz selection/
        fi
        # set filelist variable
        rm -f ${IMAGESETVARIABLE}
        cd selection/
        IMAGESETVARIABLE=`ls *.nii.gz`

        IMAGESETARRAY=()
        for IMG in $IMAGESETVARIABLE
          do
          IMAGESETARRAY[${#IMAGESETARRAY[@]}]=$IMG
          done
    fi
else
    IMAGESETARRAY=()
    for IMG in $IMAGESETVARIABLE
      do
      IMAGESETARRAY[${#IMAGESETARRAY[@]}]=$IMG
      done
fi

if [ $NUMBEROFMODALITIES -gt 1 ];
    then
    echo "--------------------------------------------------------------------------------------"
    echo " Multivariate template construction using the following ${NUMBEROFMODALITIES}-tuples:  "
    echo "--------------------------------------------------------------------------------------"
    for (( i = 0; i < ${#IMAGESETARRAY[@]}; i+=$NUMBEROFMODALITIES ))
        do
        IMAGEMETRICSET=""
        for (( j = 0; j < $NUMBEROFMODALITIES; j++ ))
            do
            k=0
            let k=$i+$j
            IMAGEMETRICSET="$IMAGEMETRICSET ${IMAGESETARRAY[$k]}"
        done
        echo $IMAGEMETRICSET
    done
    echo "--------------------------------------------------------------------------------------"
fi

# check for initial template images
for (( i = 0; i < $NUMBEROFMODALITIES; i++ ))
    do
    setCurrentImageSet $i

    if [ ! -s $REGTEMPLATES[$i] ]
        then
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Creating template ${TEMPLATES[$i]} from a population average image from the inputs."
        echo "   ${CURRENTIMAGESET[@]}"
        echo "--------------------------------------------------------------------------------------"
        ${ANTSPATH}AverageImages $DIM ${TEMPLATES[$i]} 1 ${CURRENTIMAGESET[@]}
    else
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Initial template $i found.  This will be used for guiding the registration. use : $REGTEMPLATES[$i] and $TEMPLATES[$i] "
        echo "--------------------------------------------------------------------------------------"
     # now move the initial registration template to OUTPUTNAME, otherwise this input gets overwritten.
        cp ${REGTEMPLATES[$i]} ${TEMPLATES[$i]}
    fi

    if [ ! -s ${TEMPLATES[$i]} ];
        then
        echo "Your template : $TEMPLATES[$i] was not created.  This indicates trouble!  You may want to check correctness of your input parameters. exiting."
        exit
    fi
done

# remove old job bash scripts
outdir=`dirname ${TEMPLATES[0]}`
if [ ${#outdir} -eq 0 ]
    then
    outdir=`pwd`
fi
rm -f ${outdir}/job*.sh

##########################################################################
#
# perform rigid body registration if requested
#
##########################################################################
if [ "$RIGID" -eq 1 ];
    then
    count=0
    jobIDs=""
    for (( i = 0; i < ${#IMAGESETARRAY[@]}; i+=$NUMBEROFMODALITIES ))
        do
        IMAGEMETRICSET=""
        for (( j = 0; j < $NUMBEROFMODALITIES; j++ ))
            do
            k=0
            let k=$i+$j
            IMAGEMETRICSET="$IMAGEMETRICSET -m MI[${TEMPLATES[$j]},${IMAGESETARRAY[$k]},${MODALITYWEIGHTS[$j]},32]"
        done

        qscript="${outdir}/job_${count}_qsub.sh"
        echo "$SCRIPTPREPEND" > $qscript

        IMGbase=`basename ${IMAGESETARRAY[$i]}`
        BASENAME=` echo ${IMGbase} | cut -d '.' -f 1 `
        RIGID="${outdir}/rigid${i}_0_${IMGbase}"

        exe="$ANTS $DIM $IMAGEMETRICSET -o $RIGID -i 0 --use-Histogram-Matching --number-of-affine-iterations 10000x10000x1000 $RIGIDTYPE"

        echo "$exe" > $qscript

        exe2='';
        pexe2='';
        pexe=" $exe > ${outdir}/job_${count}_metriclog.txt "
        for (( j = 0; j < $NUMBEROFMODALITIES; j++ ))
            do
            k=0
            let k=$i+$j
            IMGbase=`basename ${IMAGESETARRAY[$k]}`
            BASENAME=` echo ${IMGbase} | cut -d '.' -f 1 `
            RIGID="${outdir}/rigid${i}_${j}_${IMGbase}"
            IMGbaseBASE=`basename ${IMAGESETARRAY[$i]}`
            BASENAMEBASE=` echo ${IMGbaseBASE} | cut -d '.' -f 1 `
            exe2="$exe2 ${WARP} $DIM ${IMAGESETARRAY[$k]} $RIGID ${outdir}/rigid${i}_0_${BASENAMEBASE}Affine.txt -R ${TEMPLATES[$j]}\n"
            pexe2="$exe2 ${WARP} $DIM ${IMAGESETARRAY[$k]} $RIGID ${outdir}/rigid${i}_0_${BASENAMEBASE}Affine.txt -R ${TEMPLATES[$j]} >> ${outdir}/job_${count}_metriclog.txt\n"
        done

        echo -e "$exe2" >> $qscript;

        if [ $DOQSUB -eq 1 ];
            then
            id=`qsub -cwd -S /bin/bash -N antsBuildTemplate_rigid -v ANTSPATH=$ANTSPATH $QSUBOPTS $qscript | awk '{print $3}'`
            jobIDs="$jobIDs $id"
            sleep 0.5
        elif [ $DOQSUB -eq 4 ];
            then
            echo "cp -R /jobtmp/pbstmp.\$PBS_JOBID/* ${currentdir}" >> $qscript;
            id=`qsub -N antsrigid -v ANTSPATH=$ANTSPATH $QSUBOPTS -q nopreempt -l nodes=1:ppn=1 -l walltime=4:00:00 $qscript | awk '{print $1}'`
            jobIDs="$jobIDs $id"
            sleep 0.5
        elif [ $DOQSUB -eq 2 ];
            then
            # Send pexe and exe2 to same job file so that they execute in series
            echo $pexe >> ${outdir}/job${count}_r.sh
            echo -e $pexe2 >> ${outdir}/job${count}_r.sh
        elif [ $DOQSUB -eq 3 ];
            then
            id=`xgrid $XGRIDOPTS -job submit /bin/bash $qscript | awk '{sub(/;/,"");print $3}' | tr '\n' ' ' | sed 's:  *: :g'`
            #echo "xgrid $XGRIDOPTS -job submit /bin/bash $qscript"
            jobIDs="$jobIDs $id"
        elif  [ $DOQSUB -eq 0 ];
            then
             # execute jobs in series
             bash $qscript
        fi
        ((count++))
    done
    if [ $DOQSUB -eq 1 ];
        then
        # Run jobs on SGE and wait to finish
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS rigid registration on SGE cluster. Submitted $count jobs "
        echo "--------------------------------------------------------------------------------------"
        # now wait for the jobs to finish. Rigid registration is quick, so poll queue every 60 seconds
	${ANTSPATH}waitForSGEQJobs.pl 1 60 $jobIDs
        # Returns 1 if there are errors
        if [ ! $? -eq 0 ];
            then
            echo "qsub submission failed - jobs went into error state"
            exit 1;
        fi
    fi
    if [ $DOQSUB -eq 4 ];
        then
        # Run jobs on PBS and wait to finish
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS rigid registration on PBS cluster. Submitted $count jobs "
        echo "--------------------------------------------------------------------------------------"
               # now wait for the jobs to finish. Rigid registration is quick, so poll queue every 60 seconds
        ${ANTSPATH}waitForPBSQJobs.pl 1 60 $jobIDs
        # Returns 1 if there are errors
        if [ ! $? -eq 0 ];
            then
            echo "qsub submission failed - jobs went into error state"
            exit 1;
        fi
    fi
    # Run jobs on localhost and wait to finish
    if [ $DOQSUB -eq 2 ];
        then
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS rigid registration on max ${CORES} cpucores. "
        echo " Progress can be viewed in ${outdir}/job*_metriclog.txt"
        echo "--------------------------------------------------------------------------------------"
        jobfnamepadding #adds leading zeros to the jobnames, so they are carried out chronologically
        chmod +x ${outdir}/job*_r.sh
        $PEXEC -j ${CORES} "sh" ${outdir}/job*_r.sh
    fi
    if [ $DOQSUB -eq 3 ];
        then
        # Run jobs on XGrid and wait to finish
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS rigid registration on XGrid cluster. Submitted $count jobs "
        echo "--------------------------------------------------------------------------------------"
        # now wait for the jobs to finish. Rigid registration is quick, so poll queue every 60 seconds
        ${ANTSPATH}waitForXGridJobs.pl -xgridflags "$XGRIDOPTS" -verbose -delay 30 $jobIDs
        # Returns 1 if there are errors
        if [ ! $? -eq 0 ];
            then
            echo "XGrid submission failed - jobs went into error state"
            exit 1;
        fi
    fi

    for (( j = 0; j < $NUMBEROFMODALITIES; j++ ))
        do
        IMAGERIGIDSET=()
        for (( i = $j; i < ${#IMAGESETARRAY[@]}; i+=$NUMBEROFMODALITIES ))
            do
            k=0
            let k=$i-$j
            IMGbase=`basename ${IMAGESETARRAY[$i]}`
            BASENAME=` echo ${IMGbase} | cut -d '.' -f 1 `
            RIGID="${outdir}/rigid${k}_${j}_${IMGbase}"

            IMAGERIGIDSET[${#IMAGERIGIDSET[@]}]=$RIGID
        done
        echo
        echo  "${ANTSPATH}AverageImages $DIM ${TEMPLATES[$j]} 1 ${IMAGERIGIDSET[@]}"

	   ${ANTSPATH}AverageImages $DIM ${TEMPLATES[$j]} 1 ${IMAGERIGIDSET[@]}
    done

    # cleanup and save output in seperate folder
    mkdir ${outdir}/rigid
    mv ${outdir}/*.cfg ${outdir}/rigid*.nii.gz ${outdir}/*Affine.txt ${outdir}/rigid/
    # backup logs
    if [ $DOQSUB -eq 1 ];
	       then
	       mv ${outdir}/antsBuildTemplate_rigid* ${outdir}/rigid/
        # Remove qsub scripts
	rm -f ${outdir}/job_${count}_qsub.sh
    elif [ $DOQSUB -eq 4 ];
        then
	       mv ${outdir}/antsrigid* ${outdir}/rigid/
        # Remove qsub scripts
	  rm -f ${outdir}/job_${count}_qsub.sh
    elif [ $DOQSUB -eq 2 ];
	       then
	       mv ${outdir}/job*.txt ${outdir}/rigid/
    elif [ $DOQSUB -eq 3 ];
	       then
	       rm -f ${outdir}/job_*_qsub.sh
    fi
fi # endif RIGID

##########################################################################
#
# begin main level
#
##########################################################################

ITERATLEVEL=(` echo $MAXITERATIONS | tr 'x' ' ' `)
NUMLEVELS=${#ITERATLEVEL[@]}
#
# debugging only
#echo $ITERATLEVEL
#echo $NUMLEVELS
#echo ${ITERATIONLIMIT}
#
echo
echo "--------------------------------------------------------------------------------------"
echo " Start to build templates: ${TEMPLATES[@]}"
echo "--------------------------------------------------------------------------------------"
reportMappingParameters
#

TRANSFORMATION=''
REGULARIZATION=''
if [ "${TRANSFORMATIONTYPE}" == "EL" ]
    then
    # Mapping Parameters
    TRANSFORMATION=Elast[1]
    REGULARIZATION=Gauss[3,0.5]
    # Gauss[3,x] is usually the best option.    x is usually 0 for SyN --- if you want to reduce flexibility/increase mapping smoothness, the set x > 0.
    # We did a large scale evaluation of SyN gradient parameters in normal brains and found 0.25 => 0.5 to perform best when
    # combined with default Gauss[3,0] regularization.    You would increase the gradient step in some cases, though, to make
    # the registration converge faster --- though oscillations occur if the step is too high and other instability might happen too.
elif [ "${TRANSFORMATIONTYPE}" == "S2"  ]
    then
    # Mapping Parameters for the LDDMM style SyN --- the params are SyN[GradientStepLength,NTimeDiscretizationPoints,IntegrationTimeStep]
    # increasing IntegrationTimeStep increases accuracy in the diffeomorphism integration and takes more computation time.
    # NTimeDiscretizationPoints is set to 2 here
    TRANSFORMATION=SyN[1,2,0.05]
    REGULARIZATION=Gauss[3,0.]
elif [ "${TRANSFORMATIONTYPE}" == "SY"  ]
    then
    # Mapping Parameters for the LDDMM style SyN --- the params are SyN[GradientStepLength,NTimeDiscretizationPoints,IntegrationTimeStep]
    # increasing IntegrationTimeStep increases accuracy in the diffeomorphism integration and takes more computation time.
    # NTimeDiscretizationPoints is the number of spatial indices in the time dimension (the 4th dim when doing 3D registration)
    # increasing NTimeDiscretizationPoints increases flexibility and takes more computation time.
    # the --geodesic option enables either 1 asymmetric gradient estimation or 2 symmetric gradient estimation (the default here )
    TRANSFORMATION=" SyN[1,2,0.05] --geodesic 2 "
    REGULARIZATION=Gauss[3,0.]
elif [ "${TRANSFORMATIONTYPE}" == "LDDMM"  ]
   then
   # Mapping Parameters for the LDDMM style SyN --- the params are SyN[GradientStepLength,NTimeDiscretizationPoints,IntegrationTimeStep]
   # increasing IntegrationTimeStep increases accuracy in the diffeomorphism integration and takes more computation time.
   # NTimeDiscretizationPoints is the number of spatial indices in the time dimension (the 4th dim when doing 3D registration)
   # increasing NTimeDiscretizationPoints increases flexibility and takes more computation time.
   # the --geodesic option enables either 1 asymmetric gradient estimation or 2 symmetric gradient estimation (the default here )
   TRANSFORMATION=" SyN[1,2,0.05] --geodesic 1 "
   REGULARIZATION=Gauss[3,0.]
elif [ "${TRANSFORMATIONTYPE}" == "GR" ]
    then
    # Mapping Parameters for the greedy gradient descent (fast) version of SyN -- only needs GradientStepLength
    TRANSFORMATION=SyN[0.25]
    REGULARIZATION=Gauss[3,0]
elif [ "${TRANSFORMATIONTYPE}" == "GR_Constrained" ]
    then
    # Mapping Parameters for the greedy gradient descent (fast) version of SyN -- only needs GradientStepLength
    TRANSFORMATION=SyN[0.25]
    REGULARIZATION=Gauss[3,0.5]

elif [ "${TRANSFORMATIONTYPE}" == "EX" ]
    then
    # Mapping Parameters
    TRANSFORMATION=Exp[0.5,10]
    REGULARIZATION=Gauss[3,0.5]
elif [ "${TRANSFORMATIONTYPE}" == "DD" ]
    then
    # Mapping Parameters for diffemorphic demons style optimization Exp[GradientStepLength,NTimePointsInIntegration]
    #  NTimePointsInIntegration controls the number of compositions in the transformation update , see the DD paper
    TRANSFORMATION=GreedyExp[0.5,10]
    REGULARIZATION=Gauss[3,0.5]
else
    echo "Invalid transformation metric. Use EL, SY, S2, GR , DD or EX or type bash `basename $0` -h."
    exit 1
fi

i=0
while [ $i -lt ${ITERATIONLIMIT} ]
    do
    itdisplay=$((i+1))
    rm -f ${OUTPUTNAME}*Warp*.nii*
    rm -f ${outdir}/job*.sh
    # Used to save time by only running coarse registration for the first couple of iterations
    # But with decent initialization, this is probably not worthwhile.
    # If you uncomment this, replace MAXITERATIONS with ITERATIONS in the call to ants below
    #
    # # For the first couple of iterations, use high-level registration only
    # # eg if MAXITERATIONS=30x90x20, then for iteration 0, do 30x0x0
    # # for iteration 1 do 30x90x0, then do 30x90x20 on subsequent iterations
    # if [ $i -gt $((NUMLEVELS - 1)) ]
    #    then
    #    ITERATIONS=$MAXITERATIONS
    # else
    #
    #    ITERATIONS=${ITERATLEVEL[0]}
    #
    #    for (( n = 1 ; n < ${NUMLEVELS}; n++ ))
    #      do
    #      ITERATIONS=${ITERATIONS}x$((${ITERATLEVEL[n]} * $((n <= i)) ))
    #    done
    # fi
    # Job IDs of jobs submitted to queue in loop below
    jobIDs=""
    # Reinitialize count to 0
    count=0
    # Submit registration of each input to volume template to SGE or run locally.

    for (( j = 0; j < ${#IMAGESETARRAY[@]}; j+=$NUMBEROFMODALITIES ))
        do
        IMAGEMETRICSET=''
        exe=''
        warpexe=''
        pexe=''
        warppexe=''

        for (( k = 0; k < $NUMBEROFMODALITIES; k++ ))
            do
            l=0
            let l=$j+$k

            if [ "${METRICTYPE}" == "PR" ]
                then
                # Mapping Parameters
                METRIC=PR[
                METRICPARAMS="${MODALITYWEIGHTS[$k]},4]"
            elif [ "${METRICTYPE}" == "CC"  ]
                then
                # Mapping Parameters
                METRIC=CC[
                METRICPARAMS="${MODALITYWEIGHTS[$k]},5]"
            elif [ "${METRICTYPE}" == "MI" ]
                then
                # Mapping Parameters
                METRIC=MI[
                METRICPARAMS="${MODALITYWEIGHTS[$k]},32]"
            elif [ "${METRICTYPE}" == "MSQ" ]
                then
                # Mapping Parameters
                METRIC=MSQ[
                METRICPARAMS="${MODALITYWEIGHTS[$k]},0]"
            else
                echo "Invalid similarity metric. Use CC, MI, MSQ or PR or type bash `basename $0` -h."
                exit 1
            fi
            TEMPLATEbase=`basename ${TEMPLATES[$k]}`
            indir=`dirname ${IMAGESETARRAY[$j]}`
            if [ ${#indir} -eq 0 ]
                then
                indir=`pwd`
            fi
            IMGbase=`basename ${IMAGESETARRAY[$l]}`
            POO=${OUTPUTNAME}template${k}${IMGbase}
            OUTFN=${POO%.*.*}
            OUTFN=`basename ${OUTFN}`
            DEFORMED="${outdir}/${OUTFN}${l}WarpedToTemplate.nii.gz"

            IMGbase=`basename ${IMAGESETARRAY[$j]}`
            POO=${OUTPUTNAME}${IMGbase}
            OUTWARPFN=${POO%.*.*}
            OUTWARPFN=`basename ${OUTWARPFN}`
            OUTWARPFN="${OUTWARPFN}${j}"

            if [ $N4CORRECT -eq 1 ] ;
                then
                REPAIRED="${outdir}/${OUTFN}Repaired.nii.gz"
                exe=" $exe $N4 -d ${DIM} -b [200] -c [50x50x40x30,0.00000001] -i ${IMAGESETARRAY[$l]} -o ${REPAIRED} -s 2\n"
                pexe=" $pexe $N4 -d ${DIM} -b [200] -c [50x50x40x30,0.00000001] -i ${IMAGESETARRAY[$l]} -o ${REPAIRED} -s 2  >> ${outdir}/job_${count}_metriclog.txt\n"
                IMAGEMETRICSET="$IMAGEMETRICSET -m ${METRIC}${TEMPLATES[$k]},${REPAIRED},${METRICPARAMS}"
                warpexe=" $warpexe ${WARP} ${DIM} ${REPAIRED} ${DEFORMED} -R ${TEMPLATES[$k]} ${outdir}/${OUTWARPFN}Warp.nii.gz ${outdir}/${OUTWARPFN}Affine.txt\n"
                warppexe=" $warppexe ${WARP} ${DIM} ${REPAIRED} ${DEFORMED} -R ${TEMPLATES[$k]} ${outdir}/${OUTWARPFN}Warp.nii.gz ${outdir}/${OUTWARPFN}Affine.txt >> ${outdir}/job_${count}_metriclog.txt\n"
            else
                IMAGEMETRICSET="$IMAGEMETRICSET -m ${METRIC}${TEMPLATES[$k]},${IMAGESETARRAY[$l]},${METRICPARAMS}";
                warpexe=" $warpexe ${WARP} ${DIM} ${IMAGESETARRAY[$l]} ${DEFORMED} -R ${TEMPLATES[$k]} ${outdir}/${OUTWARPFN}Warp.nii.gz ${outdir}/${OUTWARPFN}Affine.txt\n"
                warppexe=" $warppexe ${WARP} ${DIM} ${IMAGESETARRAY[$l]} ${DEFORMED} -R ${TEMPLATES[$k]} ${outdir}/${OUTWARPFN}Warp.nii.gz ${outdir}/${OUTWARPFN}Affine.txt >> ${outdir}/job_${count}_metriclog.txt\n"
            fi

        done

        IMGbase=`basename ${IMAGESETARRAY[$j]}`
        POO=${OUTPUTNAME}${IMGbase}
        OUTWARPFN=${POO%.*.*}
        OUTWARPFN=`basename ${OUTWARPFN}${j}`

        LINEARTRANSFORMPARAMS="--number-of-affine-iterations 10000x10000x1000 --MI-option 32x16000"

        exe="$exe $ANTS ${DIM} $IMAGEMETRICSET -i ${MAXITERATIONS} -t ${TRANSFORMATION} -r $REGULARIZATION -o ${outdir}/${OUTWARPFN} --use-Histogram-Matching  $LINEARTRANSFORMPARAMS\n"
        exe="$exe $warpexe"

        pexe="$pexe $ANTS ${DIM} $IMAGEMETRICSET -i ${MAXITERATIONS} -t ${TRANSFORMATION} -r $REGULARIZATION -o ${outdir}/${OUTWARPFN} --use-Histogram-Matching  $LINEARTRANSFORMPARAMS >> ${outdir}/job_${count}_metriclog.txt\n"
        pexe="$pexe $warppexe"

        qscript="${outdir}/job_${count}_${i}.sh"

        echo -e $exe >> ${outdir}/job_${count}_${i}_metriclog.txt
        # 6 submit to SGE (DOQSUB=1), PBS (DOQSUB=4), PEXEC (DOQSUB=2), XGrid (DOQSUB=3) or else run locally (DOQSUB=0)
        if [ $DOQSUB -eq 1 ];
            then
            echo -e "$exe" > $qscript
            id=`qsub -cwd -N antsBuildTemplate_deformable_${i} -S /bin/bash -v ANTSPATH=$ANTSPATH $QSUBOPTS $qscript | awk '{print $3}'`
            jobIDs="$jobIDs $id"
            sleep 0.5
        elif [ $DOQSUB -eq 4 ];
            then
            echo -e "$SCRIPTPREPEND" > $qscript
            echo -e "$exe" >> $qscript
            echo "cp -R /jobtmp/pbstmp.\$PBS_JOBID/* ${currentdir}" >> $qscript;
            id=`qsub -N antsdef${i} -v ANTSPATH=$ANTSPATH -q nopreempt -l nodes=1:ppn=1 -l walltime=4:00:00 $QSUBOPTS $qscript | awk '{print $1}'`
            jobIDs="$jobIDs $id"
            sleep 0.5
        elif [ $DOQSUB -eq 2 ];
            then
            echo -e $pexe >> ${outdir}/job${count}_r.sh
        elif [ $DOQSUB -eq 3 ];
            then
            echo -e "$SCRIPTPREPEND" > $qscript
            echo -e "$exe" >> $qscript
            id=`xgrid $XGRIDOPTS -job submit /bin/bash $qscript | awk '{sub(/;/,"");print $3}' | tr '\n' ' ' | sed 's:  *: :g'`
            jobIDs="$jobIDs $id"
        elif  [ $DOQSUB -eq 0 ];
            then
            echo -e $exe > $qscript
            bash $qscript
        fi

        # counter updated, but not directly used in this loop
        count=`expr $count + 1`;
    #		echo " submitting job number $count " # for debugging only
    done
    # SGE wait for script to finish
    if [ $DOQSUB -eq 1 ];
        then
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS registration on SGE cluster. Iteration: $itdisplay of $ITERATIONLIMIT"
        echo "--------------------------------------------------------------------------------------"
        # now wait for the stuff to finish - this will take a while so poll queue every 10 mins
        ${ANTSPATH}waitForSGEQJobs.pl 1 600 $jobIDs
        if [ ! $? -eq 0 ];
            then
            echo "qsub submission failed - jobs went into error state"
            exit 1;
        fi
    elif [ $DOQSUB -eq 4 ];
        then
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS registration on PBS cluster. Iteration: $itdisplay of $ITERATIONLIMIT"
        echo "--------------------------------------------------------------------------------------"
        # now wait for the stuff to finish - this will take a while so poll queue every 10 mins
        ${ANTSPATH}waitForPBSQJobs.pl 1 600 $jobIDs
        if [ ! $? -eq 0 ];
            then
            echo "qsub submission failed - jobs went into error state"
            exit 1;
        fi
    fi
    # Run jobs on localhost and wait to finish
    if [ $DOQSUB -eq 2 ];
        then
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS registration on max ${CORES} cpucores. Iteration: $itdisplay of $ITERATIONLIMIT"
        echo " Progress can be viewed in job*_${i}_metriclog.txt"
        echo "--------------------------------------------------------------------------------------"
        jobfnamepadding #adds leading zeros to the jobnames, so they are carried out chronologically
        chmod +x ${outdir}/job*.sh
        $PEXEC -j ${CORES} sh ${outdir}/job*.sh
    fi
    if [ $DOQSUB -eq 3 ];
        then
        # Run jobs on XGrid and wait to finish
        echo
        echo "--------------------------------------------------------------------------------------"
        echo " Starting ANTS registration on XGrid cluster. Submitted $count jobs "
        echo "--------------------------------------------------------------------------------------"
        # now wait for the jobs to finish. This is slow, so poll less often
        ${ANTSPATH}waitForXGridJobs.pl -xgridflags "$XGRIDOPTS" -verbose -delay 300 $jobIDs
        # Returns 1 if there are errors
        if [ ! $? -eq 0 ];
            then
            echo "XGrid submission failed - jobs went into error state"
            exit 1;
        fi
    fi
    for (( j = 0; j < $NUMBEROFMODALITIES; j++ ))
        do
        shapeupdatetotemplate ${DIM} ${TEMPLATES[$j]} ${TEMPLATENAME} ${OUTPUTNAME} ${GRADIENTSTEP} ${j}
    done
    echo
    echo "--------------------------------------------------------------------------------------"
    echo " Backing up results from iteration $itdisplay"
    echo "--------------------------------------------------------------------------------------"
    mkdir ${outdir}/${TRANSFORMATIONTYPE}_iteration_${i}
    cp ${TEMPLATENAME}${j}warplog.txt ${outdir}/*.cfg ${OUTPUTNAME}*.nii.gz ${outdir}/${TRANSFORMATIONTYPE}_iteration_${i}/
    # backup logs
    if [ $DOQSUB -eq 1 ];
        then
        mv ${outdir}/antsBuildTemplate_deformable_* ${outdir}/${TRANSFORMATIONTYPE}_iteration_${i}
    elif [ $DOQSUB -eq 4 ];
        then
        mv ${outdir}/antsdef* ${outdir}/${TRANSFORMATIONTYPE}_iteration_${i}
    elif [ $DOQSUB -eq 2 ];
        then
        mv ${outdir}/job*.txt ${outdir}/${TRANSFORMATIONTYPE}_iteration_${i}
    elif [ $DOQSUB -eq 3 ];
        then
        rm -f ${outdir}/job_*.sh
    fi
    ((i++))
done
end main loop
rm -f job*.sh
#cleanup of 4D files
if [ "${range}" -gt 1 ] && [ "${TDIM}" -eq 4 ]
    then
    mv ${tmpdir}/selection/${TEMPLATES[@]} ${currentdir}/
    cd ${currentdir}
    rm -rf ${tmpdir}/
fi
time_end=`date +%s`
time_elapsed=$((time_end - time_start))
echo
echo "--------------------------------------------------------------------------------------"
echo " Done creating: ${TEMPLATES[@]}"
echo " Script executed in $time_elapsed seconds"
echo " $(( time_elapsed / 3600 ))h $(( time_elapsed %3600 / 60 ))m $(( time_elapsed % 60 ))s"
echo "--------------------------------------------------------------------------------------"

exit 0
