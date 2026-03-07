FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 1) deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git cmake pkg-config build-essential \
    libprotobuf-dev protobuf-compiler \
    libopencv-dev \
    libhdf5-dev \
    libleveldb-dev libsnappy-dev liblmdb-dev \
    libopenblas-dev \
    libboost-all-dev \
    libgflags-dev libgoogle-glog-dev \
    libgtest-dev \
    python3-dev python3-pip python3-numpy python3-setuptools python3-wheel \
 && rm -rf /var/lib/apt/lists/*

# 2) caffe
RUN git clone --depth 1 https://github.com/BVLC/caffe.git /opt/caffe
WORKDIR /opt/caffe

COPY Makefile.config /opt/caffe/Makefile.config

# 3) Fix OpenCV linking issue:
#    - Caffe Makefile รุ่นเก่ามักเพิ่ม opencv_imgcodecs เฉพาะ OPENCV_VERSION=3
#    - OpenCV4 ใช้ได้กับ branch 3 ของ Caffe ได้มากกว่า จึง force เป็น 3
#    - และเติม LIBRARIES += opencv_imgcodecs กันพลาด
RUN set -eux; \
    sed -i 's/^OPENCV_VERSION := .*/OPENCV_VERSION := 3/' Makefile.config || true; \
    grep -q '^LIBRARIES \+= opencv_imgcodecs' Makefile.config || echo 'LIBRARIES += opencv_imgcodecs' >> Makefile.config

# 4) Patch OpenCV legacy macros -> IMREAD_* (robust)
RUN set -eux; \
    cd /opt/caffe; \
    mapfile -t files < <(grep -RIl "CV_LOAD_IMAGE_" . || true); \
    if (( ${#files[@]} )); then \
      for f in "${files[@]}"; do \
        sed -i \
          -e 's/CV_LOAD_IMAGE_COLOR/cv::IMREAD_COLOR/g' \
          -e 's/CV_LOAD_IMAGE_GRAYSCALE/cv::IMREAD_GRAYSCALE/g' \
          -e 's/CV_LOAD_IMAGE_UNCHANGED/cv::IMREAD_UNCHANGED/g' \
          -e 's/CV_LOAD_IMAGE_ANYDEPTH/cv::IMREAD_ANYDEPTH/g' \
          -e 's/CV_LOAD_IMAGE_ANYCOLOR/cv::IMREAD_ANYCOLOR/g' \
          "$f" || true; \
      done; \
    fi

# 5) build
RUN make -j"$(nproc)" all

# (ถ้าคุณยังอยากให้ผ่าน pycaffe/test ทีหลังค่อยเปิด)
# RUN make -j"$(nproc)" pycaffe && make -j"$(nproc)" test

# ป้องกัน warning undefined var ตอน build
ENV PYTHONPATH=/opt/caffe/python

CMD ["/bin/bash"]
