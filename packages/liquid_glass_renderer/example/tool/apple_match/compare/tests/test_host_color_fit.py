"""Contracts for the guarded dark color objective."""

import unittest

from host_color_fit import _objective, _validate_color_coverage


def _entry(response_error: float) -> dict:
    return {
        "referenceResponseRGB8Bit": [0, 0, 0],
        "candidateResponseRGB8Bit": [response_error] * 3,
        "referenceLuminanceDelta8Bit": 0,
        "candidateLuminanceDelta8Bit": response_error,
        "referenceSaturationDelta": 0,
        "candidateSaturationDelta": response_error / 255,
    }


def _metrics(errors: dict[str, float]) -> dict:
    residual = {"meanAbsoluteError8Bit": 0.0}
    return {
        "color": {symbol: _entry(error) for symbol, error in errors.items()},
        "lighting": {
            "decomposition": {
                "transmissionResidual": {"faceOver12px": residual},
                "emissionResidual": {"faceOver12px": residual},
            },
            "black": {"faceOver12px": residual},
            "white": {"faceOver12px": residual},
        },
    }


class HostColorFitTests(unittest.TestCase):
    def test_worst_hue_is_not_hidden_by_palette_average(self):
        even_score, _ = _objective(_metrics({symbol: 2 for symbol in "RGBW"}))
        outlier_score, components = _objective(
            _metrics({"R": 0, "G": 0, "B": 8, "W": 0})
        )
        self.assertGreater(outlier_score, even_score)
        self.assertEqual(components["paletteWorstLuminanceMae8Bit"], 8)

    def test_every_declared_hue_must_have_samples(self):
        scene = {
            "probes": [
                {"id": "B", "background": {"palette": {hue: "#000" for hue in "RGBW"}}}
            ]
        }
        with self.assertRaisesRegex(ValueError, "missing declared hues"):
            _validate_color_coverage(_metrics({"R": 0, "G": 0, "B": 0}), scene)


if __name__ == "__main__":
    unittest.main()
