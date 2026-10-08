"""Use a macOS camera (including Continuity Camera) as a document scanner."""

from __future__ import annotations

import argparse
from datetime import datetime
from pathlib import Path
import time

import cv2
import numpy as np


def order_points(points: np.ndarray) -> np.ndarray:
    """Return points as top-left, top-right, bottom-right, bottom-left."""
    points = np.asarray(points, dtype=np.float32).reshape(4, 2)
    rect = np.zeros((4, 2), dtype=np.float32)
    point_sums = points.sum(axis=1)
    point_diffs = np.diff(points, axis=1).ravel()
    rect[0] = points[np.argmin(point_sums)]
    rect[2] = points[np.argmax(point_sums)]
    rect[1] = points[np.argmin(point_diffs)]
    rect[3] = points[np.argmax(point_diffs)]
    return rect


def four_point_transform(image: np.ndarray, points: np.ndarray) -> np.ndarray:
    """Crop and flatten the quadrilateral described by points."""
    top_left, top_right, bottom_right, bottom_left = order_points(points)
    width = int(
        max(
            np.linalg.norm(bottom_right - bottom_left),
            np.linalg.norm(top_right - top_left),
        )
    )
    height = int(
        max(
            np.linalg.norm(top_right - bottom_right),
            np.linalg.norm(top_left - bottom_left),
        )
    )
    if width < 2 or height < 2:
        raise ValueError("文档区域过小，无法执行透视校正")

    destination = np.array(
        [[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]],
        dtype=np.float32,
    )
    matrix = cv2.getPerspectiveTransform(
        np.array([top_left, top_right, bottom_right, bottom_left]), destination
    )
    return cv2.warpPerspective(image, matrix, (width, height))


def enhance_document(image: np.ndarray) -> np.ndarray:
    """Preserve document detail as lossless grayscale instead of hard thresholding."""
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)


def find_document(frame: np.ndarray) -> tuple[np.ndarray | None, float]:
    """Find the largest plausible four-sided document in a frame."""
    ratio = max(frame.shape[0] / 500.0, 1.0)
    preview = cv2.resize(
        frame,
        (round(frame.shape[1] / ratio), round(frame.shape[0] / ratio)),
        interpolation=cv2.INTER_AREA,
    )
    gray = cv2.cvtColor(preview, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(gray, 75, 200)
    edges = cv2.morphologyEx(
        edges, cv2.MORPH_CLOSE, np.ones((5, 5), dtype=np.uint8), iterations=2
    )
    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    minimum_area = preview.shape[0] * preview.shape[1] * 0.15

    for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:10]:
        hull = cv2.convexHull(contour)
        hull_area = cv2.contourArea(hull)
        if hull_area < minimum_area or cv2.contourArea(contour) < hull_area * 0.8:
            continue
        perimeter = cv2.arcLength(hull, True)
        polygon = cv2.approxPolyDP(hull, 0.02 * perimeter, True)
        if len(polygon) == 4:
            return polygon, ratio
    return None, ratio


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Mac/iPhone 连续互通高拍仪")
    parser.add_argument("--camera", type=int, default=0, help="摄像头索引（默认：0）")
    parser.add_argument(
        "--output", type=Path, default=Path("scanned_docs"), help="保存目录"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    capture = cv2.VideoCapture(args.camera, cv2.CAP_AVFOUNDATION)
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 3840)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 2160)
    if not capture.isOpened():
        print(f"错误：无法打开摄像头索引 {args.camera}。")
        print("先在“系统设置 → 隐私与安全性 → 相机”中允许当前终端使用摄像头。")
        print("再确认 FaceTime 的“视频”菜单中能看到 iPhone；索引不存在时不要继续递增。")
        return 1

    args.output.mkdir(parents=True, exist_ok=True)
    print("启动成功：窗口聚焦后按 s 扫描，按 q 退出。")
    print(
        "实际画面："
        f"{int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))}x"
        f"{int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))}"
    )

    try:
        while True:
            ok, frame = capture.read()
            if not ok:
                print("未能获取画面帧，正在重试……")
                time.sleep(0.5)
                continue

            original = frame.copy()
            document, ratio = find_document(frame)
            if document is not None:
                outline = np.rint(document * ratio).astype(np.int32)
                cv2.drawContours(frame, [outline], -1, (0, 255, 0), 2)

            cv2.imshow("Mac Document Scanner", frame)
            key = cv2.waitKey(1) & 0xFF
            if key == ord("q"):
                break
            if key != ord("s"):
                continue
            if document is None:
                debug_path = args.output / f"debug_{datetime.now():%Y%m%d_%H%M%S_%f}.jpg"
                if cv2.imwrite(str(debug_path), original):
                    print(f"未检测到文档；已保存调试原图：{debug_path}")
                else:
                    print("未检测到文档，且调试原图保存失败。")
                continue

            try:
                cropped = four_point_transform(
                    original, document.reshape(4, 2).astype(np.float32) * ratio
                )
                processed = enhance_document(cropped)
                path = args.output / f"scan_{datetime.now():%Y%m%d_%H%M%S_%f}.png"
                if not cv2.imwrite(
                    str(path), processed, [cv2.IMWRITE_PNG_COMPRESSION, 3]
                ):
                    raise OSError("OpenCV 未能写入文件")
                print(f"已保存：{path}")
            except (cv2.error, OSError, ValueError) as error:
                print(f"保存失败：{error}")
    finally:
        capture.release()
        cv2.destroyAllWindows()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
