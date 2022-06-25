#!/bin/sh

test_description='Check to build, install, and test RPMs'

. "$(dirname "$0")/sharness.sh"

if test "x${chaos}" != xt; then
    skip_all='skipping rpm test; chaos not enabled'
    test_done
fi

if egrep '^ID.*=.*\b(rhel|fedora)\b' /etc/os-release >/dev/null 2>&1; then :; else
    skip_all='skipping rpm test; not a redhat-based system'
    test_done
fi

if rpm --query --all | grep ^munge-; then
    skip_all='skipping rpm test; munge rpm already installed'
    test_done
fi

if type rpmbuild >/dev/null 2>&1; then :; else
    skip_all='skipping rpm test; rpmbuild not installed'
    test_done
fi

if test_have_prereq SUDO; then :; else
    skip_all='skipping rpm test; sudo not enabled'
    test_done
fi

test_expect_success 'setup' '
    MUNGE_RPM_DIR="${TMPDIR:-"/tmp"}/munge-rpm-$$" &&
    mkdir -p "${MUNGE_RPM_DIR}"
'

test_expect_success 'create dist tarball' '
    cd "${MUNGE_BUILD_DIR}" &&
    rm -f munge-*.tar.xz &&
    make dist &&
    mv munge-*.tar.xz "${MUNGE_RPM_DIR}"/ &&
    cd &&
    MUNGE_TARBALL=$(ls "${MUNGE_RPM_DIR}"/munge-*.tar.xz) &&
    test -f "${MUNGE_TARBALL}" &&
    test_set_prereq MUNGE_TARBALL
'

test_expect_success MUNGE_TARBALL 'build srpm' '
    rpmbuild -ts --without=check --without=verify \
            --define="_builddir %{_topdir}/BUILD" \
            --define="_buildrootdir %{_topdir}/BUILDROOT" \
            --define="_rpmdir %{_topdir}/RPMS" \
            --define="_sourcedir %{_topdir}/SOURCES" \
            --define="_specdir %{_topdir}/SPECS" \
            --define="_srcrpmdir %{_topdir}/SRPMS" \
            --define="_topdir ${MUNGE_RPM_DIR}" \
            "${MUNGE_TARBALL}" &&
    test_set_prereq MUNGE_SRPM
'

test_expect_success MUNGE_SRPM 'install builddeps' '
    local BUILDDEP &&
    if type -p dnf; then BUILDDEP="dnf builddep --assumeyes"; \
            elif type -p yum-builddep; then BUILDDEP="yum-builddep"; fi &&
    sudo ${BUILDDEP} "${MUNGE_RPM_DIR}"/SRPMS/*.src.rpm
'

test_expect_success MUNGE_TARBALL 'build rpm' '
    rpmbuild -tb --without=check --without=verify \
            --define="_builddir %{_topdir}/BUILD" \
            --define="_buildrootdir %{_topdir}/BUILDROOT" \
            --define="_rpmdir %{_topdir}/RPMS" \
            --define="_sourcedir %{_topdir}/SOURCES" \
            --define="_specdir %{_topdir}/SPECS" \
            --define="_srcrpmdir %{_topdir}/SRPMS" \
            --define="_topdir ${MUNGE_RPM_DIR}" \
            "${MUNGE_TARBALL}" &&
    test_set_prereq MUNGE_RPM
'

test_expect_success MUNGE_RPM 'install rpm' '
    sudo rpm --install --verbose "${MUNGE_RPM_DIR}"/RPMS/*/*.rpm \
            >rpm.install.out.$$ &&
    cat rpm.install.out.$$
'

test_expect_success MUNGE_RPM 'query keyfile name' '
    MUNGE_KEYFILE=$(/usr/sbin/mungekey --help | \
            sed -ne "/--keyfile/ s/.*\[\([^]]*\)\].*/\1/p") &&
    test -n "${MUNGE_KEYFILE}" &&
    echo "${MUNGE_KEYFILE}"
'

test_expect_success MUNGE_RPM 'create key' '
    sudo --user=munge /usr/sbin/mungekey --force --verbose
'

test_expect_success MUNGE_RPM 'check key' '
    sudo --user=munge test -f "${MUNGE_KEYFILE}"
'

test_expect_success MUNGE_RPM 'start munge service' '
    sudo systemctl start munge
'

test_expect_success MUNGE_RPM 'check service status' '
    systemctl status --full munge
'

test_expect_success MUNGE_RPM 'encode credential' '
    munge </dev/null >cred.$$
'

test_expect_success MUNGE_RPM 'decode credential' '
    unmunge <cred.$$
'

test_expect_success MUNGE_RPM 'replay credential' '
    test_must_fail unmunge <cred.$$
'

test_expect_success MUNGE_RPM 'stop munge service' '
    sudo systemctl stop munge
'

test_expect_success MUNGE_RPM 'remove rpm' '
    grep ^munge- rpm.install.out.$$ >rpm.pkgs.$$ &&
    sudo rpm --erase --verbose $(cat rpm.pkgs.$$)
'

test_expect_success MUNGE_RPM 'verify rpm removal' '
    rpm --query --all >rpm.query.out.$$ &&
    ! grep ^munge- rpm.query.out.$$
'

test_expect_success MUNGE_RPM 'remove key' '
    local MUNGE_KEYFILEDIR=$(dirname "${MUNGE_KEYFILE}") &&
    expr "${MUNGE_KEYFILEDIR}" : "/.*/munge$" >/dev/null 2>&1 &&
    echo "${MUNGE_KEYFILEDIR}" &&
    sudo rm -rf "${MUNGE_KEYFILEDIR}" &&
    test_set_prereq SUCCESS
'

test_expect_success SUCCESS 'cleanup' '
    rm -rf "${MUNGE_RPM_DIR}"
'

test_done
