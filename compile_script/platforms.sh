#!/bin/bash

source_code_platforms=(immortalwrt)

immortalwrt_value='{"REPO_URL": "https://github.com/immortalwrt/immortalwrt.git","REPO_BRANCH": "openwrt-25.12","CONFIGS": "config/immortalwrt_config","DIY_P1_SH": "diy_script/immortalwrt_diy/diy-part1.sh","DIY_P2_SH": "diy_script/immortalwrt_diy/diy-part2.sh","DIY_P3_SH": "diy_script/immortalwrt_diy/diy-part3.sh","OS": "ubuntu-latest"}'

immortalwrt_platforms=(X86)

copy_backgroundfiles_platforms=(X86)

matrix_json="["
source_matrix_json="["

for source_platform in "${source_code_platforms[@]}"; do

    platforms_var="${source_platform}_platforms[@]"
    platforms=("${!platforms_var}")
    value_var="${source_platform}_value"
    value="${!value_var}"

    source_matrix_json+="{\"source_code_platform\":\"${source_platform}\",\"value\":${value}},"

    for platform in "${platforms[@]}"; do
        matrix_json+="{\"source_code_platform\":\"${source_platform}\",\"platform\":\"${platform}\",\"value\":${value}},"
    done
done

matrix_json="${matrix_json%,}]"
source_matrix_json="${source_matrix_json%,}]"



echo $matrix_json
echo $source_matrix_json
echo "matrix=$matrix_json" >> $GITHUB_OUTPUT
echo "source_matrix_json=$source_matrix_json" >> $GITHUB_OUTPUT
