"""Protect the same paper wallet's previously observed profitable price peak.

This is NOT a guaranteed trade execution or future profit prediction.
It only produces an exit signal from an observed spot peak/short trough.
Risk/reward targets are gross, before fee/slippage; larger gaps may exceed a
stop. Only the existing single-wallet SELL/COVER path may realize a trade.
"""
import math

# Hard gross-price adverse excursions observed at scheduled market checks.
SPOT_HARD_STOP_PCT = 0.028
SHORT_HARD_STOP_PCT = 0.025

# Price first moved favorably at least 1.2% before reversing at least 0.85%.
# The original trailing rule requires the *current* mark still show >0.4% profit.
# That could miss an entire giveback and let the position reach a -4.5% stop.
ARM_GAIN_PCT = 0.012
MIN_PEAK_RETRACEMENT_PCT = 0.0085
NEAR_ENTRY_PCT = 0.004


def _good(*numbers):
    return all(isinstance(x, (int, float)) and not isinstance(x, bool)
               and math.isfinite(x) and x > 0 for x in numbers)


def spot_giveback(entry, current, observed_peak):
    """Candidate SPOT SELL after a previously observed favorable peak is lost."""
    if not _good(entry, current, observed_peak) or observed_peak < current:
        return False
    peak_up = observed_peak / entry - 1
    retrace = 1 - current / observed_peak
    current_up = current / entry - 1
    return (peak_up >= ARM_GAIN_PCT
            and retrace >= MIN_PEAK_RETRACEMENT_PCT
            and current_up <= NEAR_ENTRY_PCT)


def short_giveback(entry, current, observed_trough):
    """Candidate SHORT COVER after a favorable trough is mostly lost."""
    if not _good(entry, current, observed_trough) or observed_trough > current:
        return False
    favorable = 1 - observed_trough / entry
    rebound = current / observed_trough - 1
    remaining = 1 - current / entry
    return (favorable >= ARM_GAIN_PCT
            and rebound >= MIN_PEAK_RETRACEMENT_PCT
            and remaining <= NEAR_ENTRY_PCT)
