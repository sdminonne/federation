package(default_visibility = ["//visibility:public"])

load(
    "@io_bazel_rules_go//go:def.bzl",
    "go_library",
    "go_test",
)

go_library(
    name = "go_default_library",
    srcs = ["configfiles.go"],
    importpath = "k8s.io/kubernetes/pkg/kubelet/kubeletconfig/configfiles",
    deps = [
        "//vendor/k8s.io/apimachinery/pkg/runtime/serializer:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/apis/kubeletconfig:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/apis/kubeletconfig/scheme:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/kubeletconfig/util/codec:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/util/filesystem:go_default_library",
    ],
)

filegroup(
    name = "package-srcs",
    srcs = glob(["**"]),
    tags = ["automanaged"],
    visibility = ["//visibility:private"],
)

filegroup(
    name = "all-srcs",
    srcs = [":package-srcs"],
    tags = ["automanaged"],
)

go_test(
    name = "go_default_test",
    srcs = ["configfiles_test.go"],
    importpath = "k8s.io/kubernetes/pkg/kubelet/kubeletconfig/configfiles",
    library = ":go_default_library",
    deps = [
        "//vendor/github.com/davecgh/go-spew/spew:go_default_library",
        "//vendor/k8s.io/apimachinery/pkg/api/equality:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/apis/kubeletconfig:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/apis/kubeletconfig/scheme:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/apis/kubeletconfig/v1alpha1:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/kubeletconfig/util/files:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/kubelet/kubeletconfig/util/test:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/util/filesystem:go_default_library",
    ],
)
