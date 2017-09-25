FROM zultron/docker-cross-builder:jessie
MAINTAINER John Morris <john@zultron.com>

###################################################################
# Build configuration settings

env DEBIAN_ARCH=armhf
env SYS_ROOT=/sysroot/armhf
env HOST_MULTIARCH=arm-linux-gnueabihf
env DISTRO=jessie
env EXTRA_FLAGS=

###################################################################
# Environment (computed)

ENV CPPFLAGS="--sysroot=$SYS_ROOT ${EXTRA_FLAGS}"
ENV LDFLAGS="--sysroot=$SYS_ROOT ${EXTRA_FLAGS}"
ENV PKG_CONFIG_PATH="$SYS_ROOT/usr/lib/$HOST_MULTIARCH/pkgconfig:$SYS_ROOT/usr/lib/pkgconfig:$SYS_ROOT/usr/share/pkgconfig"
ENV DPKG_ROOT=$SYS_ROOT
ENV PATH=/usr/lib/ccache:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/bin:$SYS_ROOT/usr/bin

###################################################################
# Configure apt for Machinekit

# add Machinekit package archive
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 43DDF224
# FIXME temporary for stretch
RUN if test $DISTRO = stretch; then \
        echo "deb http://deb.mgware.co.uk $DISTRO main" > \
            /etc/apt/sources.list.d/machinekit.list; \
    else \
	echo "deb http://deb.machinekit.io/debian jessie main" > \
            /etc/apt/sources.list.d/machinekit.list; \
    fi

###################################################################
# Install Machinekit dependency packages

##############################
# Configure multistrap

# Set up debian/control for `mk-build-deps`
#     FIXME download parts from upstream
ADD debian/ /tmp/debian/
# FIXME no Xenomai in Stretch
# RUN /tmp/debian/configure -prxt8.6
RUN /tmp/debian/configure -prt8.6

# Add multistrap configurations
ADD jessie.conf raspbian.conf stretch-rpi.conf stretch.conf /tmp/

# Directory for `mk-build-deps` apt repository
RUN mkdir /tmp/debs && \
    touch /tmp/debs/Sources

# Create deps package
RUN if test $DISTRO = jessie; then \
        mk-build-deps --arch $DEBIAN_ARCH /tmp/debian/control; \
    else \
        mk-build-deps --build-arch $DEBIAN_ARCH --host-arch $DEBIAN_ARCH \
	    /tmp/debian/control; \
    fi && \
    mv *.deb /tmp/debs && \
    ( cd /tmp/debs && dpkg-scanpackages -m . > /tmp/debs/Packages )

# Add deps repo to apt sources
RUN echo "deb file:///tmp/debs ./" > /etc/apt/sources.list.d/local.list

# Update apt cache
RUN apt-get update


##############################
# Host arch build environment

# Build "sysroot"
# - Select and unpack build dependency packages
RUN if test $DEBIAN_ARCH = amd64; then \
        echo "Installing machinekit-build-deps package"; \
        apt-get install -y  -o Apt::Get::AllowUnauthenticated=true \
            machinekit-build-deps; \
    else \
        echo "Multistrapping from /tmp/$DISTRO.conf"; \
        multistrap -f /tmp/$DISTRO.conf -a $DEBIAN_ARCH -d $SYS_ROOT; \
    fi
# - Fix symlinks in "sysroot" libdir pointing to `/lib/$MULTIARCH`
RUN if ! test $DEBIAN_ARCH = amd64; then \
        for link in $(find $SYS_ROOT/usr/lib/${HOST_MULTIARCH}/ -type l); do \
            if test $(dirname $(readlink $link)) != .; then \
                ln -sf ../../../lib/${HOST_MULTIARCH}/$(basename \
                    $(readlink $link)) $link; \
            fi; \
        done; \
    fi
# - Link tcl/tk setup scripts
RUN test $DEBIAN_ARCH = amd64 || { \
        mkdir -p /usr/lib/${HOST_MULTIARCH} && \
        ln -s $SYS_ROOT/usr/lib/${HOST_MULTIARCH}/tcl8.6 \
            /usr/lib/${HOST_MULTIARCH} && \
        ln -s $SYS_ROOT/usr/lib/${HOST_MULTIARCH}/tk8.6 \
            /usr/lib/${HOST_MULTIARCH}; \
        }

# - Link directories with glib/gtk includes in the wrong place
RUN test $DEBIAN_ARCH = amd64 || { \
	ln -s $SYS_ROOT/usr/lib/${HOST_MULTIARCH}/glib-2.0 \
	    /usr/lib/${HOST_MULTIARCH}; \
	ln -s $SYS_ROOT/usr/lib/${HOST_MULTIARCH}/gtk-2.0 \
	    /usr/lib/${HOST_MULTIARCH}; \
	}

##############################
# Build arch build environment

# Install Multi-Arch: foreign dependencies
RUN apt-get install -y \
        cython \
        uuid-runtime \
        protobuf-compiler \
        python-protobuf \
        python-pyftpdlib \
        python-tk \
        netcat-openbsd \
        tcl8.6 tk8.6
# FIXME not available in stretch
#        libxenomai-dev

# Monkey-patch entire /usr/include, and re-add build-arch headers
RUN test $DEBIAN_ARCH = amd64 || { \
        mv /usr/include /usr/include.build && \
        ln -s $SYS_ROOT/usr/include /usr/include; \
	ln -sf /usr/include.build/x86_64-linux-gnu $SYS_ROOT/usr/include; \
    }
