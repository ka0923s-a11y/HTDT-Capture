# lane-d — iterative segmentation + spatial fusion (#269)

Protocol revision: **v1** (initial scaffold)

Measure independently: screen/UI seed reprojection error in portrait AND landscape; 2D mask IoU/boundary quality; refinement count/time; qualityLevel trade-off; supported-depth fraction; 3D centroid/extent/footprint error; background/support-plane contamination; unresolved rate; resource effect.

Compare the legacy orientation/display-transform route with the iOS 27 `viewRotationAngle` route when the final SDK supports it. A clean mask without spatial support is not successful 3D geometry.
