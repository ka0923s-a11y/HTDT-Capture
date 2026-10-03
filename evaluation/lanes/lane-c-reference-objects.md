# lane-c — reference objects (#268)

Protocol revision: **v1** (initial scaffold)

Physical/numerical ground truth: translation/orientation repeatability/error; native equipment vs calibrated marker; standard vs extended training where both plausible; source USDZ scale sensitivity; similar-object false matches; occlusion/view angle/distance; loss/reacquisition; detection vs tracking workload; RoomPlan/depth coexistence.

Record the training manifest/digests (xcrun createml objecttracker args, USDZ digest, toolchain, negative examples) so every reference-object revision is explainable.
