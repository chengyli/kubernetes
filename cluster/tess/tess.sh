#!/usr/bin/env bash

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/../..


function tess::scp () {

	SCP=${SCP:="scp ${SSH_CONFIG:=-F $HOME/.ssh/${TESS_CLUSTER:-config}}"}

	isFile=true
	files=()
	targets=()
	for arg in "${@}"; do
	   if [[ "$arg" == '--' ]]; then
			isFile=false
			continue
	   fi
	   if ${isFile}; then
		   files+=("$arg")
	   else
		   targets+=("$arg")
	   fi
	done


	IFS=',' read -r -a env_targets <<< "$SCP_TARGETS"
	targets+=("${env_targets[@]}")

	echo -n "files: ${files[@]}, "
	echo "destinations: ${targets[@]} "

	for target in "${targets[@]}"; do
		if [[ ! "$target" =~ .*:.* ]]; then
			echo "scp target $target does not have path separator"
			exit 1
		fi
		echo "$SCP ${files[@]} ${target}"
		eval "$SCP ${files[@]} ${target}"
	done
}

function tess::ssh () {
	local ssh_cmd=${SSH:-"ssh ${SSH_CONFIG:=-F $HOME/.ssh/${TESS_CLUSTER:-config}}"}
	echo ">> $ssh_cmd $*"
	$ssh_cmd $@

}

function tess::scp-kubelet () {
	target_host=$1
	if [[ -z $target_host ]]; then
		echo "need the target host location (for e.g 'host:/path' to scp the kubelet binary to"
		exit 1
	fi
	if [[ -r "$KUBE_ROOT/_output/local/bin/linux/amd64/kubelet" ]]; then
		tess::scp "$KUBE_ROOT/_output/local/bin/linux/amd64/kubelet" "--" "$@"
	elif [[ -r $KUBE_ROOT/_output/dockerized/bin/linux/amd64/kubelet ]]; then
		tess::scp "$KUBE_ROOT/_output/dockerized/bin/linux/amd64/kubelet" "--" "$@"
	else
		echo "kubelet binary not found, did you make release?"
	fi
}

function tess::restart-kubelet () {
	target_host=$1
	if [[ -z $target_host ]]; then
		echo "need the name of host to restart the kubelet process on"
		exit 1
	fi
	tess::ssh  -t $target_host \
		"'cp /usr/local/bin/kubelet ~/kubelet$(date +%Y-%m-%dT%H:%M:%S) \
		&& sudo systemctl stop kubelet \
		&& sudo cp ~/kubelet /usr/local/bin/kubelet \
		&& sudo systemctl start kubelet'"
}



function tess::scp-kube-binary () {
	local binary=$1
	if [[ -z $binary ]]; then
		echo "need the name of binary to scp, eg: kube-apiserver"
		exit 1
	fi
	shift

	local file="$KUBE_ROOT/_output/release-stage/server/linux-amd64/kubernetes/server/bin/${binary}"
	if [[ -r "${file}" ]]; then
		tess::scp "${file}.tar" "--" "$@"
		if [[ -r "${file}.docker_tag" ]]; then
			tess::scp "${file}.docker_tag" "--" "$@"
		fi
	else
		echo "kubelet binary $binary not found @_output/release-stage/server/linux-amd64/kubernetes/server/bin , did you make release?"
	fi
}

function tess::scp-apiserver () {
	local servers=()
	for server in "$@"; do
		if [[ "$server" =~ .*:.* ]]; then
			echo "just server, without paths please. we will copy it to the home dir"
			exit 1
		fi
		servers+=("${server}:~")
	done
	tess::scp-kube-binary kube-apiserver "${servers[@]}"
}

# modifies the manifest file to load the apiserver binary from the host path. For
# testing out the local changes easily, handy with sync.sh.
# todo (fix the docker version on the template to be the latest)
function tess::restart-api () {
	target_host=$1
	if [[ -z $target_host ]]; then
		echo "need the name of host to restart the kubelet process on"
		exit 1
	fi

	tess scp _output/local/bin/linux/amd64/kube-apiserver cluster/tess/debug/kube-apiserver.manifest -- "$target_host:"
	tess::ssh -T $target_host << 'EOSSH'
	 sudo rm -f /etc/kubernetes/manifests/kube-apiserver.manifest
	 sudo docker ps | grep kube-api | awk '{print $1}' | sudo xargs -r docker kill
	 sudo cp ~/kube-apiserver /srv/kubernetes/temp/
	 sudo cp ~/kube-apiserver.manifest /etc/kubernetes/manifests/
EOSSH
}

function tess::scp-controller-manager () {
	tess::scp-kube-binary kube-controller-manager "$@"
}

function tess::scp-scheduler () {
	tess::scp-kube-binary kube-scheduler "$@"
}

function tess::scp-proxy () {
	tess::scp-kube-binary kube-proxy "$@"
}

function tess::cluster () {
	echo "${TESS_CLUSTER:-unspecified}"
}

function tess::uday () {
	 echo "uday"
	}

function tess::sshconfig () {
   echo "$HOME/.ssh/${TESS_CLUSTER:-unspecified}"
}

function tess::add-sshconfig () {
	HOST=${1:-$HOST}
	NAME=${2:-$NAME}
	: ${HOST:?need HOST}
	: ${NAME:?need NAME}

	cat <<-EOF >> "$HOME/.ssh/${TESS_CLUSTER:-unspecified}"
	HOST $HOST
		HOSTNAME $NAME
EOF
}

function tess::gen-sshconfig () {
	# todo, check for existence
	cat <<-EOF > "$HOME/.ssh/${TESS_CLUSTER:-unspecified}"
	Host *
	IdentityFile $HOME/.ssh/id_kubernetes_${TESS_CLUSTER:-unspecified}
	User fedora
EOF
}

function tess::clone-shallow () {
	: ${BRANCH:='tess-master'}
	# --single-branch is redundant with --depth, but just in case :)
	git clone --single-branch --depth 1 --branch $BRANCH git@github.corp.ebay.com:tess/kubernetes.git
}

# --- Invoke functions -----

method=$1

if [[ -z $method ]]; then
	echo "need at least one argument"
	exit 1
fi

shift
"tess::$method" $@
