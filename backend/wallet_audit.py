"""Cost-basis reconciliation, independent of market prices.

No deposits/withdrawals exist in this paper model. This checks internal
accounting consistency, not completeness of the truncated trade tape.
"""
import math


def reconcile(state):
    def number(value, nonnegative=False):
        if (isinstance(value, bool) or not isinstance(value, (int, float))
                or not math.isfinite(value) or (nonnegative and value < 0)):
            raise ValueError('Invalid accounting value')
        return value
    try:
        cash = number(state['cashTry'], True)
        initial = number(state['initialCashTry'], True)
        realized = number(state['realizedTry'])
        spot_basis = 0.0
        short_basis = 0.0
        for pos in state.get('holdings', {}).values():
            if number(pos['quantity'], True) <= 0:
                raise ValueError('Invalid quantity')
            spot_basis += number(pos['costTry'], True)
        for pos in state.get('shorts', {}).values():
            if number(pos['quantity'], True) <= 0:
                raise ValueError('Invalid quantity')
            short_basis += number(pos['marginTry'], True) + number(pos['entryFeeTry'], True)
        actual = cash + spot_basis + short_basis
        expected = initial + realized
        delta = actual - expected
        tolerance = max(1e-6, abs(expected) * 1e-9)
        return {'status': 'PASS' if abs(delta) <= tolerance else 'MISMATCH',
                'basisTotalTry': actual, 'expectedTry': expected,
                'differenceTry': delta, 'toleranceTry': tolerance,
                'scope': 'cash-and-open-cost-basis'}
    except (KeyError, TypeError, ValueError, AttributeError):
        return {'status': 'INVALID', 'scope': 'cash-and-open-cost-basis'}
