package(default_visibility = ["//visibility:public"])

load(
    "@io_bazel_rules_go//go:def.bzl",
    "go_binary",
    "go_library",
)

go_binary(
    name = "federation-controller-manager",
    importpath = "k8s.io/federation/cmd/federation-controller-manager",
    library = ":go_default_library",
)

go_library(
    name = "go_default_library",
    srcs = ["controller-manager.go"],
    importpath = "k8s.io/federation/cmd/federation-controller-manager",
    deps = [
        "//cmd/federation-controller-manager/app:go_default_library",
        "//cmd/federation-controller-manager/app/options:go_default_library",
        "//vendor/github.com/spf13/pflag:go_default_library",
        "//vendor/k8s.io/apiserver/pkg/server/healthz:go_default_library",
        "//vendor/k8s.io/apiserver/pkg/util/flag:go_default_library",
        "//vendor/k8s.io/apiserver/pkg/util/logs:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/util/reflector/prometheus:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/util/workqueue/prometheus:go_default_library",
        "//vendor/k8s.io/kubernetes/pkg/version/verflag:go_default_library",
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
    srcs = [
        ":package-srcs",
        "//cmd/federation-controller-manager/app:all-srcs",
    ],
    tags = ["automanaged"],
)
