#!/bin/bash

remote_branch="develop"
default_branch="develop"
gerrit_user=cn1208
github_user=GYZHANG2019
ma35_vsi_libs_branch="$default_branch"
ma35_ffmpeg_branch="$default_branch"
ma35_linux_kernel_branch="$default_branch"
ma35_osal_branch="$default_branch"
ma35_zsp_firmware_branch="$default_branch"
ma35_shelf_branch="$default_branch"
ma35_tools_branch="$default_branch"
ma35_ddbi_branch="$default_branch"
ma35_xma_branch="develop"
ma35_apps_branch="develop"
ma35_branch="$default_branch"
amd_gits_mirror=y
extra_update=y
try_gerrit=y

function create_folder(){
    folder=supernova_`date "+%m%d%H%M"`
    mkdir $folder &&
    cd $folder &&
    ln -s ../$0 . &&
    echo $folder
}

repos=(ma35_vsi_libs ma35_ffmpeg ma35_linux_kernel ma35_tools ma35 ma35_ddbi ma35_xma ma35_apps ma35_osal ma35_zsp_firmware ma35_shelf)

function sync_fork(){
    cd $root;
    idx=1
    for repo in ${repos[@]}; do
        cd $repo
        if (( $? != 0 )); then
            echo "repo $repo is not exist"
            exit 1
        fi
        echo -e "\n$idx. sync $repo..."
        branch=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f2-)
        remote=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f1)
        url=$(git remote -v | grep "fetch" | grep $remote)
        user=${url##*:}
        user=${user%%/*}
        if [[ "$(echo $url | grep gerrit)" == "" ]]; then
            gh repo sync -b $branch --force $user/$repo
            if (( $? != 0 )); then
                echo "gh repo sync failed"
                exit 1
            fi
            echo "$user/$repo...$branch had been synced"
        else
            echo "$repo is not a fork, skip"
        fi
        idx=$((idx+1))
        cd ..
    done
    echo "fetch_amd_gits done"
}

#delete old fork and create new fork
function reset_fork(){
    cd $root;
    idx=1
    for repo in ${repos[@]}; do
        echo -e "\ndeleting $repo"
        gh repo delete $github_user/$repo --confirm
        echo "fork $repo"
        gh repo fork Xilinx-Projects/$repo --clone=false
        idx=$((idx+1))
    done
    echo "reset_fork done"
}

function sync(){
    cd $root;
    idx=1
    for repo in ${repos[@]}; do
        cd $repo
        branch=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f2-)
        remote=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f1)
        echo -e "\n$idx. updating $repo...$branch"
        git config pull.rebase false
        git pull $remote $branch
        idx=$((idx+1))
        cd ..
    done
    echo "fetch_amd_gits done"
}

function reset(){
    cd $root;
    idx=1
    for repo in ${repos[@]}; do
        cd $repo
        git clean -xdf
        if [[ "$1" != "" ]]; then
            branch=$1
        else
            branch=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f2-)
        fi
        remote=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f1)
        echo -e "\n$idx. updating $repo...$branch"
        git merge --abort 2> /dev/null
        git reset $remote/$branch --hard
        idx=$((idx+1))
        cd ..
    done
    echo "fetch_amd_gits done"
}

function merge(){
    gits=${repos[@]}
    idx=1
    cd $root
    for repo in ${gits[@]}; do
        if [[ "$repo" == "ma35_xma" ]] || [[ "$repo" == "ma35_app" ]]; then
            continue
        fi
        cd $repo
        branch=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f2-)
        remote=$(git branch -a | grep "\->" | cut -d ">" -f 2 | cut -d'/' -f1)
        echo "$idx. $repo..."
        git checkout $remote/$branch -f 2>/dev/null
        git fetch $remote > /dev/null
        log=$(git merge $remote/$remote_branch --no-ff)
        if (( $? != 0 )); then
            echo -e "error! merge conflict on $repo\n"
        elif [[ "$log" != "Already up to date." ]]; then
            git push $remote HEAD:refs/for/$branch
            if (( $? != 0 )); then
                echo -e "push $repo failed\n"
            else
                echo -e "merge $repo was done\n"
            fi
        else
            echo -e "no changes\n"
        fi
        idx=$((idx+1))
        cd ..
    done
}

function clone(){
    gits=${repos[@]}
    cd $root;
    idx=1
    sudo rm ma35/build -rf
    if [[ "$amd_gits_mirror" == "y" ]]; then
        repo init --no-clone-bundle -u ssh://${gerrit_user}@gerrit-spsd.verisilicon.com:29418/manifest -b spsd/master -m Transcoding/supernova_ma35_spsd_develop.xml
        repo sync
    else
        for repo in ${gits[@]}; do
            git="git@github.com:$github_user/$repo.git"
            branch=$repo"_branch"
            branch=`eval echo '$'"$branch"`
            echo -e "\n$idx. clone $git...$branch"
            rm $repo -rf
            git clone "$git" -b $branch
            if (( $? != 0 )); then
                echo "git clone $git failed"
                if [[ $try_gerrit == "y" ]]; then
                    git="ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/$repo"
                    git clone "$git" -b $branch
                    if (( $? != 0 )); then
                        echo "git clone $git failed"
                        exit 1
                    fi
                else
                    exit 1
                fi
            fi
            idx=$((idx+1))
        done
    fi
    echo "clone_amd_gits done"
}

function build(){
    echo "Building full project with CMake..."
    echo $root
    cd $root
    if [ ! -d ma35/build ]; then
        mkdir ma35/build
    fi

    # Use $(uname -r) as kernel version by default. If this version
    # is not found in /usr/src, use the first kernel version in /usr/src.
    # This happens when building with docker which uses same kernel as
    # host but it has own kernel header sources.
    local kernel_version=$(uname -r)
    if ! ls -1 /usr/src | grep ${kernel_version} > /dev/null; then
        kernel_version=$(ls -1 /usr/src/ | grep -e generic -e amd64 |
        sed 's/linux-headers-//g' | head -1)
    fi
    kernel_version=$(echo $kernel_version | sed 's/-generic//g')

    cd ma35/build
    cmake $root/ma35 -G Ninja -DMA35_REPO_TAG=$remote_branch -DCMAKE_BUILD_TYPE=Debug -DMA35_FORCE_NO_PRIVATE_repos=true -DREPO_USE_LOCAL_shelf=true -DREPO_USE_LOCAL_vsi_libs=true -DREPO_USE_LOCAL_tools=true -DREPO_USE_LOCAL_linux_kernel=true -DREPO_USE_LOCAL_osal=true -DREPO_USE_LOCAL_ddbi=true -DREPO_USE_LOCAL_xma=true -DREPO_USE_LOCAL_apps=true -DREPO_USE_LOCAL_ma35=true -DREPO_USE_LOCAL_ffmpeg=true -DREPO_USE_LOCAL_zsp_firmware=true -DMA35_KERNEL_MODULE_VERSION=${kernel_version}
    ninja
    ninja ffmpeg_vsi
    if (( $? != 0 )); then
        exit 1;
    fi
    ninja kernel_module
    if (( $? != 0 )); then
        exit 1;
    fi
    cd -
    make_firmware
    if (( $? != 0 )); then
        exit 1;
    fi
}

function remove_rpath(){
    cd $1 1>&/dev/null
    patchelf --remove-rpath ffmpeg
    libs=(common h2enc g2dec cache)
    for lib in ${libs[@]}; do
        patchelf --remove-needed _deps/vsi_libs-build/src/vpe/prebuild/lib$lib.so ./libvpi.so
    done
    cd - 1>&/dev/null
}

function make_firmware(){
    export PATH=/usr/local/ZSP/ZView5.16.0/cmdtools/bin:$PATH
    export LD_LIBRARY_PATH=/usr/local/ZSP/ZView5.16.0/cmdtools/lib:$LD_LIBRARY_PATH
    make -C ma35_zsp_firmware/firmware
}

function install(){
    cd $(ls -d $root/ma35/build/out/*/ | head -n 1)
    ./install.sh
}

function package(){
    build_path=$1
    if [[ "$build_path" == "" ]]; then
        build_path=ma35/build
    elif [[ ! -d $build_path ]]; then
        echo "path $build_path is not available"
        exit 1
    fi
    cd $root
    build_path=$(realpath $build_path)
    version=$(grep -o '".*"' $root/ma35_vsi_libs/src/vpe/inc/version.h | sed 's/"//g')
    output_pkg_name=cmake_vpe_package_x86_64_linux_$version
    outpath=$build_path/out/$output_pkg_name
    echo "Generating MA35 software installation package at $(realpath $build_path)..."

    rm $outpath -rf && mkdir -p $outpath 2>/dev/null
    mkdir $outpath/cmodel/
    mkdir $outpath/firmware/
    mkdir $outpath/JSON/independent/ -p
    mkdir $outpath/JSON/independent_physical/ -p

    ## copy libs
    echo "1. copying libs..."
    cp $build_path/_deps/vsi_libs-build/src/vpe/src/libvpi.so $outpath/ -rf
    cp $build_path/_deps/vsi_libs-build/sdk/VIP2D/hal/user/libGAL.so $outpath/
    cp $build_path/_deps/vsi_libs-build/sdk/VIP2D/driver/khronos/libOpenVX/driver/src/libOpenVX.so $outpath/
    cp $build_path/_deps/ffmpeg-build/ffmpeg $outpath/
    cp $build_path/_deps/ffmpeg-build/libavfilter/libavfilter.so* $outpath/
    cp $build_path/_deps/ffmpeg-build/libswscale/libswscale.so* $outpath/
    cp $build_path/_deps/ffmpeg-build/libavdevice/libavdevice.so* $outpath/
    cp $build_path/_deps/ffmpeg-build/libavformat/libavformat.so* $outpath/
    cp $build_path/_deps/ffmpeg-build/libswresample/libswresample.so* $outpath/
    cp $build_path/_deps/ffmpeg-build/libavcodec/libavcodec.so* $outpath/
    cp $build_path/_deps/ffmpeg-build/libavutil/libavutil.so* $outpath/
    # cp $build_path/_deps/sn_int_ext-build/lib/libsn_int.so $outpath/
    cp $build_path/_deps/ddbi-build/lib/jsf_mamgmt/libjsf_mamgmt.so $outpath/
    cp $build_path/_deps/ddbi-build/lib/jsf_mautil/libjsf_mautil.so $outpath/
    cp $build_path/_deps/ddbi-build/lib/jsf_xrm/libjsf_xrm.so $outpath/
    cp $build_path/_deps/ddbi-build/testapps/jmamgmt $outpath/
    cp $build_path/_deps/ddbi-build/testapps/jmautil $outpath/
    cp $build_path/_deps/ddbi-build/testapps/jxrm $outpath/
    cp $build_path/_deps/apps-build/xrm_apps/xrm_interface/libxrm_interface.so $outpath/
    cp $build_path/_deps/tools-build/log_ama/liblog_ama.so $outpath/
    cp $root/ma35_shelf/xma/libxma.so* $outpath/
    cp $root/ma35_shelf/roi_scale/libroi_scale.so $outpath
    cp $root/ma35_vsi_libs/sdk/VIP2D/compiler/libVSC/x86_64/libVSC.so $outpath

    ## copy firmware
    echo "2. copying firmware..."
    cp $root/ma35_shelf/firmware_platform/* $outpath/firmware/ -rf
    cp ma35_zsp_firmware/firmware/tools/output/zsp_firmware_packed_pcie.bin $outpath/firmware/supernova_zsp_fw_evb.bin &&
    cp ma35_zsp_firmware/firmware/tools/output/zsp_firmware_packed.bin $outpath/firmware/supernova_zsp_fw_evb_flash.bin

    ## copy cmodel related
    echo "3. copying cmodel files..."
    # cp $root/ma35_shelf/ma35_sn_int/*.so $outpath/cmodel/
    # cp $root/ma35_shelf/host_device_algo/*.so $outpath/

    ## copy drivers
    echo "4. copying driver source code..."
    cp $root/ma35_linux_kernel/ $root/drivers -rf 2>/dev/null
    cd $root/drivers/src 1>/dev/null && ./build_driver.sh clean 1>/dev/null && rm .git -rf && cd - 1>/dev/null
    cp $root/ma35_osal/src/include/* $root/drivers/src -rf
    tar -czf $outpath/drivers.tgz drivers
    rm $root/drivers -rf

    ## copy scripts
    echo "5. copying test scripts..."
    cp $root/ma35_vsi_libs/src/vpe/build/install.sh $outpath/
    cp $root/ma35_vsi_libs/src/vpe/tools/*.sh $outpath/

    # copy model files
    echo "6. copying VIP model files..."
    find $root/ma35_vsi_libs/src/vpe/src/processor/vip/model/ -type f -name *.json -exec cp {} $outpath/JSON/independent/ \;
    mv $outpath/JSON/independent/*physical*.json $outpath/JSON/independent_physical/
    find  $root/ma35_vsi_libs/src/vpe/src/processor/vip/model/ -type f -name *.nb -exec cp {} $outpath/JSON/independent/ \;
    mv $outpath/JSON/independent/*physical*.nb $outpath/JSON/independent_physical/

    echo "7. removing ffmpeg rpath..."
    remove_rpath $outpath

    echo "8. copying latest ffprobe and stest.sh"
    if [[ "$extra_update" == "y" ]]; then
        git archive --remote=ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/ma35_vsi_libs spsd/develop src/vpe/prebuild/libs/x86_64_linux/ffprobe | tar xO > $outpath/ffprobe
        git archive --remote=ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/ma35_vsi_libs spsd/develop src/vpe/prebuild/firmware/ctrl_prefetchable_VF_PF_BAR4_512_class_code_Gen4.bin | tar xO > $outpath/firmware/ctrl_prefetchable_VF_PF_BAR4_512_class_code_Gen4.bin
        git archive --remote=ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/ma35_vsi_libs spsd/develop src/vpe/tools/stest.sh | tar xO > $outpath/stest.sh
        git archive --remote=ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/ma35_vsi_libs spsd/develop src/vpe/tools/smoke_test.sh | tar xO > $outpath/smoke_test.sh
        git archive --remote=ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/ma35_vsi_libs spsd/develop src/vpe/build/install.sh | tar xO > $outpath/install.sh
        chmod 777 $outpath/*.sh  $outpath/ffprobe
    fi

    echo "9. packaging..."
    cd $outpath/../ 1>&/dev/null
    tar -czf $output_pkg_name.tgz $output_pkg_name/

    echo "9. done! package was generated: `pwd`/$output_pkg_name"
}

function help(){
    echo "$0 --amd_gits_mirror=:            y/n, whether enable the gits mirror.[$amd_gits_mirror] "
    echo "$0 --gerrit_user=:                set the gerrit account wich contains VSI gits.[$gerrit_user]"
    echo "$0 --github_user=:                set the github account wich contains gits.[$github_user]"
    echo "$0 --extra_update=:               get some files update from gerrit.[$extra_update]"
    echo "$0 --default_branch=:             default branch name.[$default_branch]"
    echo "$0 --ma35_vsi_libs_branch=:       set the vsi_lib branch name.[$ma35_vsi_libs_branch]"
    echo "$0 --ma35_ffmpeg_branch=:         set the ffmpeg branch name.[$ma35_ffmpeg_branch]"
    echo "$0 --ma35_linux_kernel_branch=:   set the drivers branch name.[$ma35_linux_kernel_branch]"
    echo "$0 --ma35_osal_branch=:           set the drivers branch name.[$ma35_osal_branch]"
    echo "$0 --ma35_zsp_firmware_branch=:   set the drivers branch name.[$ma35_zsp_firmware_branch]"
    echo "$0 --ma35_branch=:                set the ma35 branch name.[$ma35_branch]"
    echo "$0 --ma35_shelf_branch=:          set the shelf branch name.[$ma35_shelf_branch]"
    echo "$0 new:                           create one new empty folder."
    echo "$0 clone:                         clone all of the gits"
    echo "$0 sync:                          sync the full codebase."
    echo "$0 sync_fork:                     If you worked on a forked github codebase, this command can help to sync from main git."
    echo "$0 reset_fork:                    delete old fork and create new fork."
    echo "$0 reset [branch]:                reset all repos to target branch, if target branch is not specified, then reset to default remote branch"
    echo "$0 merge:                         merge remote changes to head of gits"
    echo "$0 build:                         do full build"
    echo "$0 clean:                         clean the build"
    echo "$0 install:                       install the built files into your system"
    echo "$0 pr [CLs]:                      create PR automatically. CLs MUST be in same repo."
}

function check(){
    if (( $1 != 0 )); then
        echo "error($1) on command:"
        echo "$2"
        exit 1
    fi
}

function create_pr(){
    cls=("$@")

    if [[ "$cls" == "" ]] || [[ "$(echo $cls | grep gerrit)" == "" ]]; then
        echo "invalid gerrit CL"
        exit 1
    fi

    branch=pr$(date "+%d%H%M%S")
    echo "will release below CLs on branch $branch:"
    for cl in ${cls[@]}; do
        echo $cl
    done
    repo=$(echo ${cls[0]} | grep -o 'ma35[^/]*')
    if [[ "$(echo ${repos[@]} | grep $repo)" == "" ]]; then
        echo "repo '$repo' is not valid"
        exit
    fi
    cd $repo

    if [[ "$(git remote -v | awk '{print $1}' | grep gerrit)" == "" ]]; then
        cmd="git remote add gerrit ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/$repo 2>/dev/null"
        echo $cmd | sh || check $? "$cmd"
    fi
    cmd="git fetch gerrit $default_branch 2>/dev/null"
    echo $cmd | sh || check $? "$cmd"

    cmd="git checkout origin/$remote_branch -f 2>/dev/null"
    echo $cmd | sh || check $? "$cmd"

    cmd="git branch -D $branch 2>/dev/null"
    echo $cmd | sh

    cmd="git checkout -b $branch 2>/dev/null"
    echo $cmd | sh || check $? "$cmd"

    echo -e "\n1. cherry-pick changes"
    for cl in ${cls[@]}; do
        echo " $cl..."
        change_id=$(echo $cl | grep -oP '\+/+\K[0-9]+')
        for (( patch_set=10; patch_set--; patch_set>0 )); do
            cmd="git fetch ssh://$gerrit_user@gerrit-spsd.verisilicon.com:29418/github/Xilinx-Projects/$repo refs/changes/${change_id: -2}/$change_id/$patch_set && git cherry-pick FETCH_HEAD"
            echo $cmd | sh 2> err.log
            ret=$?
            if (( $ret == 128 )); then
                continue
            elif (( $ret == 1 )); then
                echo "cherry-pick $cl failed, log:"
                cat err.log
                return 1
            elif (( $ret == 0 )); then
                echo "cherry-pick $cl done"
                break
            fi
        done
    done

    echo -e "\n2. push changes to branch: $branch"
    cmd="git push origin $branch 2>/dev/null"
    echo $cmd | sh || check $? "$cmd"

    cmd="gh pr create -R Xilinx-Projects/$repo --head $github_user:$branch --base $remote_branch --fill"
    echo -e "\n3. creating PR"
    pr_link=$(echo $cmd | sh)
    check $? "$cmd"
    echo -e "PR had been created: \n $pr_link"
}

function clean()
{
    rm $root/ma35/build -rf
    find $root -name *.o | xargs rm
}

if [ -d ../ma35 ]; then
    root=`pwd`/../
else
    root=`pwd`
fi

if [[ "$1" == "" ]]; then
    build && package
    exit 0
fi

for (( i=1; i <=$#; i++ )); do
    opt=${!i}
    optarg="${opt#*=}"
    next_opt=$((i+1))
    next_value=${!next_opt}
    case "$opt" in
    --amd_gits_mirror=*)
        echo "amd_gits_mirror=$optarg"
        amd_gits_mirror=$optarg;;
    --gerrit_user=*)
        echo "gerrit_user=$optarg"
        gerrit_user=$optarg;;
    --github_user=*)
        echo "github_user=$optarg"
        github_user=$optarg;;
    --extra_update=*)
        echo "extra_update=$optarg"
        extra_update=$optarg;;
    --default_branch=*)
        default_branch=$optarg
        ma35_vsi_libs_branch="$default_branch"
        ma35_ffmpeg_branch="$default_branch"
        ma35_linux_kernel_branch="$default_branch"
        ma35_osal_branch="develop"
        ma35_zsp_firmware_branch="$default_branch"
        ma35_shelf_branch="$default_branch"
        ma35_tools_branch="$default_branch"
        ma35_branch="$default_branch"
        ma35_xma_branch="$default_branch"
        ma35_ddbi_branch="$default_branch";;
    --ma35_vsi_libs_branch=*)
        echo "ma35_vsi_libs_branch=$optarg"
        ma35_vsi_libs_branch=$optarg;;
    --ma35_ffmpeg_branch=*)
        echo "ma35_ffmpeg_branch=$optarg"
        ma35_ffmpeg_branch=$optarg;;
    --ma35_linux_kernel_branch=*)
        echo "ma35_linux_kernel_branch=$optarg"
        ma35_linux_kernel_branch=$optarg;;
    --ma35_osal_branch=*)
        echo "ma35_osal_branch=$optarg"
        ma35_osal_branch=$optarg;;
    --ma35_zsp_firmware_branch=*)
        echo "ma35_zsp_firmware_branch=$optarg"
        ma35_zsp_firmware_branch=$optarg;;
    --ma35_branch=*)
        echo "ma35_branch=$optarg"
        ma35_branch=$optarg;;
    --ma35_shelf_branch=*)
        echo "ma35_shelf_branch=$optarg"
        ma35_shelf_branch=$optarg;;
    new)
        root=$(realpath $(create_folder))
        echo "new project $root had been created";;
    clone)
        clone;;
    sync)
        sync;;
    pr)
        i=$((i+1)); create_pr "${@:$i}" ;;
    sync_fork)
        sync_fork;;
    reset_fork)
        reset_fork;;
    reset)
        i=$((i+1)); reset ${@:$i};;
    merge)
        merge;;
    build)
        build
        package;;
    install)
        install;;
    clean)
        clean;;
    --help|help)
        help
        exit 0;;
    *)
        echo "invalid input $optarg"
        help
        exit 1;;
    esac
done
