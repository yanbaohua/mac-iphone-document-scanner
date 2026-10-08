import unittest

import cv2
import numpy as np

from scanner import enhance_document, find_document, four_point_transform, order_points


class ScannerTests(unittest.TestCase):
    def test_orders_points(self):
        points = np.array([[90, 80], [10, 10], [10, 80], [90, 10]])
        expected = np.array([[10, 10], [90, 10], [90, 80], [10, 80]])
        np.testing.assert_array_equal(order_points(points), expected)

    def test_flattens_quadrilateral(self):
        image = np.zeros((120, 160, 3), dtype=np.uint8)
        points = np.array([[20, 10], [140, 20], [130, 100], [30, 110]])
        flattened = four_point_transform(image, points)
        self.assertGreater(flattened.shape[0], 75)
        self.assertGreater(flattened.shape[1], 110)

    def test_enhancement_preserves_gray_detail(self):
        gradient = np.tile(np.arange(256, dtype=np.uint8), (80, 1))
        image = cv2.cvtColor(gradient, cv2.COLOR_GRAY2BGR)

        enhanced = enhance_document(image)

        self.assertEqual(enhanced.shape, gradient.shape)
        self.assertGreater(len(np.unique(enhanced)), 2)

    def test_finds_large_document(self):
        frame = np.zeros((600, 800, 3), dtype=np.uint8)
        cv2.rectangle(frame, (100, 80), (700, 520), (255, 255, 255), -1)
        document, ratio = find_document(frame)
        self.assertIsNotNone(document)
        self.assertEqual(ratio, 1.2)

    def test_finds_document_with_interrupted_edges(self):
        frame = np.zeros((600, 800, 3), dtype=np.uint8)
        cv2.rectangle(frame, (100, 80), (700, 520), (255, 255, 255), -1)
        cv2.rectangle(frame, (380, 70), (420, 160), (0, 0, 0), -1)
        cv2.rectangle(frame, (380, 440), (420, 530), (0, 0, 0), -1)
        cv2.rectangle(frame, (90, 280), (180, 320), (0, 0, 0), -1)
        cv2.rectangle(frame, (620, 280), (710, 320), (0, 0, 0), -1)

        document, _ = find_document(frame)

        self.assertIsNotNone(document)


if __name__ == "__main__":
    unittest.main()
