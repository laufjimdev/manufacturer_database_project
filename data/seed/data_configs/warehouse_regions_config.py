WAREHOUSE_REGIONS = {
    "W1": [  # National Central Hub (Ohio)
        "OH", "MI", "IN", "KY", "PA", "NY", "NJ", "CT", "RI", "MA",
        "VT", "NH", "ME", "MD", "DE", "VA", "WV", "NC", "SC", "GA",
        "FL", "TN", "AL", "MS", "DC",
    ],
    "W2": [  # South Central Distribution (Dallas)
        "TX", "OK", "AR", "LA", "KS",
    ],
    "W3": [  # Northeast Distribution (Chicago)
        "IL", "WI", "MN", "IA", "MO", "NE", "ND", "SD",
    ],
    "W4": [  # Inland Empire (California)
        "CA", "OR", "WA", "NV", "AZ", "UT", "ID", "MT", "WY", "CO", "NM",
        "AK", "HI",
    ],
}


def get_state_to_warehouse_map():

    state_map = {}
    for warehouse_id, states in WAREHOUSE_REGIONS.items():
        for state in states:
            state_map[state] = warehouse_id
    return state_map