#!/bin/sh

#  Created by Mat Hammond on 18/11/2016.
#  Copyright © 2016 BBC RD. All rights reserved.
#
#  Copyright 2015 British Broadcasting Corporation
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.


COMMON="jazzy.common.yaml"
COMMON_SUBPROJ="jazzy.common-subproject-header.yaml"

# must have trailing slash...
REPO_BROWSE_ROOT="https://github.com/bbc/dvbcss-synckit-ios/tree/master/"
DOCS_BASE_URL_NO_SCHEMENAME="://bbc.github.io/dvbcss-synckit-ios/latest/"


PARALLEL=false

function show_help {
	(
		echo "Builds documentation using jazzy."
		echo "Must be run while in same directory as this script."
		echo ""
		echo "Usage:"
		echo ""
		echo "    $0 [--parallel]"
		echo ""
		echo "Where:"
		echo "  --parallel    Parallelise the running of jazzy for all subprojects simultaneously."
		echo ""
	) >&2
}

while :; do
	case "$1" in
		-h|-\?|/\?|--help)
			show_help
			exit
			;;
		--parallel)
			PARALLEL=true
			;;
		--)
			shift
			break
			;;
		*)
			break
	esac
	shift
done


(
	cd ..

	# 1) Process READMEs to create version with following changes:
	#    a) multi-line sections removed that are delimited by
	#          [](---START EXCLUDE FROM DOC BUILD---)
	#             ...
	#          [](---END EXCLUDE FROM DOC BUILD---)
	#
	#    b) rewrite relative URLs that are not purely fragment URLs to point to github
	#       (basically URLs not beginning with a scheme such as 'http:' or with '#')

	for README_FILE in `find . -name README.md`; do
		MODIFIED_README_FILE="${README_FILE/README.md/doc-build-README.md}"
		
		PATH_IN_REPO=`dirname "$README_FILE" | sed -e 's/^.\///'`

		echo "Preprocessing $README_FILE"
		echo "... writing out as $MODIFIED_README_FILE"
		echo "... $PATH_IN_REPO"

		cat "$README_FILE" | perl -0777 -pe '\
			s"\Q[](---START EXCLUDE FROM DOC BUILD---)\E.*?\Q[](---END EXCLUDE FROM DOC BUILD---)\E\s*\n?""gs; \
			s"(\[[^]]+\]\()(?![a-zA-Z][-.+0-9a-zA-Z]*:)([^#)][^)]*\))"\1'${REPO_BROWSE_ROOT}${PATH_IN_REPO}'/\2"gs; ' > "$MODIFIED_README_FILE"

	done

	# 2) Generate config files for jazzy by concatenating common elements with each
	#    sub-project's jazzy config template

	# we do the 'root' first, as a special case. This 'cleans' the directory structure for
	# then the others get put in subdirs within this
	(
		cd docs
		cat "jazzy.root.template.yaml" "jazzy.common.yaml" > "jazzy.merged.yaml"
		jazzy --config jazzy.merged.yaml
	)

	# now we do the rest
	export WAIT_PIDS=
	for CONFIG_TEMPLATE in `find . -name jazzy.template.yaml`; do
		echo "Processing jazzy template: $CONFIG_TEMPLATE";
		
		SUBDIR=`dirname "$CONFIG_TEMPLATE"`
		cat "$CONFIG_TEMPLATE" "docs/$COMMON" "docs/$COMMON_SUBPROJ" > "$SUBDIR/jazzy.merged.yaml"
		
		pushd .
		cd $SUBDIR;
		jazzy --config jazzy.merged.yaml &
		JAZZY_PID=$!
		popd
		if $PARALLEL; then
			WAIT_PIDS="$WAIT_PIDS $JAZZY_PID"
		else
			wait $JAZZY_PID
		fi
	done
	
	if $PARALLEL; then
		wait $WAIT_PIDS
	fi

)

# Finally, post-process the HTML output to rewrite URLs of the form:
#          http://bbc.github.io/dvbcss-synckit-ios/latest/XXXX
#       as relative URLs of the form:
#          ../XXXX
#
# we do this as a post-processing step because the location of the HTML file in the directory
# structure is not known in advance when it is still a README.md file.
(
	cd build
	
	find . -name '*.html' | while read HTML_FILE; do
		echo "Processing: $HTML_FILE"
		RELATIVE_PREFIX=`dirname "$HTML_FILE" | tr -Cd '/' | sed -e 's"/"../"g'`
		perl -0777 -pi -e 's"https?\Q'${DOCS_BASE_URL_NO_SCHEMENAME}'\E"'${RELATIVE_PREFIX}'"gs;' "$HTML_FILE"
	done
)
	