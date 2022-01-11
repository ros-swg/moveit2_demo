ARG FROM_IMAGE=ros:foxy
ARG OVERLAY_WS=/opt/ros/overlay_ws

# multi-stage for caching
FROM $FROM_IMAGE AS cacher

# copy overlay source
ARG OVERLAY_WS
WORKDIR $OVERLAY_WS
COPY ./overlay ./
RUN vcs import src < overlay.repos && \
    vcs import src < src/ros-planning/moveit2_tutorials/moveit2_tutorials.repos

# copy manifests for caching
WORKDIR /opt
RUN mkdir -p /tmp/opt && \
    find ./ -name "package.xml" | \
      xargs cp --parents -t /tmp/opt && \
    find ./ -name "COLCON_IGNORE" | \
      xargs cp --parents -t /tmp/opt || true

# multi-stage for building
FROM $FROM_IMAGE AS builder
ARG DEBIAN_FRONTEND=noninteractive

# install helpful developer tools
RUN apt-get update && apt-get install -y \
      bash-completion \
      byobu \
      ccache \
      fish \
      glances \
      micro \
      nano \
      python3-argcomplete \
      tree \
      vim \
    && rm -rf /var/lib/apt/lists/*

# install overlay dependencies
ARG OVERLAY_WS
WORKDIR $OVERLAY_WS
COPY --from=cacher /tmp/$OVERLAY_WS/src ./src
RUN . /opt/ros/$ROS_DISTRO/setup.sh && \
    apt-get update && rosdep update \
      --rosdistro $ROS_DISTRO && \
    apt-get upgrade -y && \
    rosdep install -q -y \
      --from-paths src \
      --ignore-src \
    && rm -rf /var/lib/apt/lists/*

# build overlay source
COPY --from=cacher $OVERLAY_WS/src ./src
ARG OVERLAY_MIXINS="release ccache"
RUN . /opt/ros/$ROS_DISTRO/setup.sh && \
    colcon build \
      --symlink-install \
      --mixin $OVERLAY_MIXINS

# generate artifacts for keystore
ENV MOVEIT2_DEMO_DIR $OVERLAY_WS/..
WORKDIR $MOVEIT2_DEMO_DIR
COPY policies policies
RUN . $OVERLAY_WS/install/setup.sh && \
    ros2 security generate_artifacts -k keystore \
      -p policies/moveit2_gazebo_policy.xml

# copy demo files
COPY configs configs
COPY .gazebo /root/.gazebo

# source overlay workspace from entrypoint
ENV OVERLAY_WS $OVERLAY_WS
RUN sed --in-place \
      's|^source .*|source "$OVERLAY_WS/install/setup.bash"|' \
      /ros_entrypoint.sh && \
    cp /etc/skel/.bashrc ~/ && \
    echo 'source "$OVERLAY_WS/install/setup.bash"' >> ~/.bashrc
