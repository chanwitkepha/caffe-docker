FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 1) deps (+ pycaffe deps)

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git cmake pkg-config build-essential \
    libprotobuf-dev protobuf-compiler \
    libopencv-dev \
    libhdf5-dev \
    libleveldb-dev libsnappy-dev liblmdb-dev \
    libopenblas-dev \
    libboost-all-dev \
    libboost-python-dev \
    libgflags-dev libgoogle-glog-dev \
    libgtest-dev \
    python3-dev python3-pip python3-numpy python3-setuptools python3-wheel \
    python3-protobuf \
    python3-skimage \
 && rm -rf /var/lib/apt/lists/*

# 2) caffe
RUN git clone --depth 1 https://github.com/BVLC/caffe.git /opt/caffe
WORKDIR /opt/caffe

COPY Makefile.config /opt/caffe/Makefile.config

# 3) Fix OpenCV linking issue (เหมือนเดิม)
RUN set -eux; \
    sed -i 's/^OPENCV_VERSION := .*/OPENCV_VERSION := 3/' Makefile.config || true; \
    grep -q '^LIBRARIES \+= opencv_imgcodecs' Makefile.config || echo 'LIBRARIES += opencv_imgcodecs' >> Makefile.config

# 3.1) เปิด Python layer สำหรับ pycaffe (สำคัญมาก)
RUN set -eux; \
    grep -q '^WITH_PYTHON_LAYER := 1' Makefile.config || echo 'WITH_PYTHON_LAYER := 1' >> Makefile.config

# 4) Patch OpenCV legacy macros -> IMREAD_* (เหมือนเดิม)
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

# 5) build caffe + pycaffe
RUN make -j"$(nproc)" all && \
    make -j"$(nproc)" pycaffe

# 6) ให้ python หา caffe module ได้
ENV PYTHONPATH=/opt/caffe/python


# เพิ่มบรรทัดนี้: ให้ dynamic linker หา libcaffe.so ได้
ENV LD_LIBRARY_PATH=/opt/caffe/.build_release/lib:/opt/caffe/build/lib:${LD_LIBRARY_PATH}

# 7) sanity check: ต้องผ่าน
RUN python3 -c "import caffe; print('Caffe with Python3 is working!')"

CMD ["/bin/bash"]
