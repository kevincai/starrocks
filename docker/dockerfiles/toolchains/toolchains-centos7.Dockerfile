# Build toolchains on centos7, dev-env image can be built based on this image for centos7
# NOTE: build context MUST be set to `docker/dockerfiles/toolchains/`
#  DOCKER_BUILDKIT=1 docker build --rm=true -f docker/dockerfiles/toolchains/toolchains-centos7.Dockerfile -t toolchains-centos7:latest docker/dockerfiles/toolchains/

ARG GCC_INSTALL_HOME=/opt/rh/gcc-toolset-10/root
ARG GCC_10_DOWNLOAD_URL=https://ftp.gnu.org/gnu/gcc/gcc-10.3.0/gcc-10.3.0.tar.gz
ARG GCC_DOWNLOAD_URL=https://ftp.gnu.org/gnu/gcc/gcc-14.3.0/gcc-14.3.0.tar.gz
ARG CMAKE_INSTALL_HOME=/opt/cmake
ARG MAVEN_VERSION=3.6.3
ARG JDK_INSTALL_HOME=/opt/jdk17
ARG MAVEN_INSTALL_HOME=/opt/maven
# Can't upgrade to a later version, due to incompatible changes between 2.31 and 2.32
ARG BINUTILS_SRPM_URL=https://cdn-thirdparty.starrocks.com/centos7%2Fbinutils-2.30-108.el8.src.rpm
# Install epel-release directly from the url link
ARG EPEL_RPM_URL=https://archives.fedoraproject.org/pub/archive/epel/7/x86_64/Packages/e/epel-release-7-14.noarch.rpm
ARG COMMIT_ID=unset


FROM centos:centos7 AS fixed-centos7-image
# Fix the centos mirrorlist, due to official list is gone after EOL
ADD yum-mirrorlist /etc/yum-mirrorlist/
RUN rm -f /etc/yum.repos.d/CentOS-*.repo && ln -s /etc/yum-mirrorlist/$(arch)/CentOS-Base-Local-List.repo /etc/yum.repos.d/CentOS-Base-Local-List.repo


FROM fixed-centos7-image AS base-builder
RUN yum install -y gcc gcc-c++ make automake curl wget gzip gunzip zip bzip2 file texinfo && yum clean metadata


FROM base-builder AS binutils-builder
# build binutils from source RPM
ARG BINUTILS_SRPM_URL

RUN yum install -y bison gettext flex zlib-devel dejagnu zlib-static glibc-static sharutils libstdc++-static rpm-build && yum clean metadata
COPY build_binutils.sh /workspace/
RUN /workspace/build_binutils.sh --binutils-srpm-url ${BINUTILS_SRPM_URL} --rpms-dir /opt/rpms


FROM base-builder AS gcc-builder
ARG GCC_INSTALL_HOME
ARG GCC_10_DOWNLOAD_URL
ARG GCC_DOWNLOAD_URL
ARG GCC_10_INSTALL_HOME=/opt/gcc-10

COPY build_gcc.sh /workspace/
# Copy and install binutils-2.30 RPMs from binutils-builder before building GCC
COPY --from=binutils-builder /opt/rpms/binutils-2.30-*.rpm /tmp/
RUN rpm -Uvh /tmp/binutils-2.30-*.rpm

# Build gcc-10 using the script
RUN /workspace/build_gcc.sh \
    --gcc-version 10 \
    --gcc-download-url ${GCC_10_DOWNLOAD_URL} \
    --workspace-dir /workspace/gcc10 \
    --gcc-install-home ${GCC_10_INSTALL_HOME}

# Build gcc-14 using the script, with gcc-10 as bootstrap compiler
RUN /workspace/build_gcc.sh \
    --gcc-version 14 \
    --gcc-download-url ${GCC_DOWNLOAD_URL} \
    --workspace-dir /workspace/gcc14 \
    --gcc-install-home ${GCC_INSTALL_HOME} \
    --bootstrap-gcc-path ${GCC_10_INSTALL_HOME}

FROM fixed-centos7-image

ARG GCC_INSTALL_HOME
ARG CMAKE_INSTALL_HOME
ARG JDK_INSTALL_HOME
ARG MAVEN_VERSION
ARG MAVEN_INSTALL_HOME
ARG EPEL_RPM_URL
ARG COMMIT_ID

LABEL org.opencontainers.image.source="https://github.com/StarRocks/starrocks"
LABEL com.starrocks.commit=${COMMIT_ID}

# Create ccache directory
RUN mkdir -p  /opt/rpms /root/.ccache
# Install binutils from RPMs
# Following rpm packages will be generated in binutils-builder:
# - binutils-2.30-108.el7.{x86_64|aarch64}.rpm
# - binutils-debuginfo-2.30-108.el7.{x86_64|aarch64}.rpm
# - binutils-devel-2.30-108.el7.{x86_64|aarch64}.rpm
COPY --from=binutils-builder /opt/rpms/*.rpm /opt/rpms/
COPY install_dependencies.sh /tmp/

RUN yum-config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo && yum install -y gh && \
        yum install -y ${EPEL_RPM_URL} && yum install -y wget unzip bzip2 patch bison byacc flex autoconf automake make \
        libtool which git ccache python3 file less psmisc \
        /opt/rpms/binutils-2.30-*.rpm /opt/rpms/binutils-devel-2.30-*.rpm && \
        localedef --no-archive -i en_US -f UTF-8 en_US.UTF-8 && \
        yum clean all && rm -rf /var/cache/yum

RUN /tmp/install_dependencies.sh \
    --cmake-home ${CMAKE_INSTALL_HOME} \
    --jdk-home ${JDK_INSTALL_HOME} \
    --maven-home ${MAVEN_INSTALL_HOME} \
    --maven-version ${MAVEN_VERSION} && \
    rm -f /tmp/install_dependencies.sh

# Install gcc - copy from the GCC installation directory defined in build_gcc.sh
COPY --from=gcc-builder ${GCC_INSTALL_HOME} ${GCC_INSTALL_HOME}

# GCC configured with --prefix=/usr and installed with DESTDIR=${GCC_INSTALL_HOME}
ENV STARROCKS_GCC_HOME=${GCC_INSTALL_HOME}/usr
ENV JAVA_HOME=${JDK_INSTALL_HOME}
ENV MAVEN_HOME=${MAVEN_INSTALL_HOME}
ENV LANG=en_US.UTF-8
