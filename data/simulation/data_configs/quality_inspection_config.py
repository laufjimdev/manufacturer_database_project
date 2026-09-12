QUALITY_INSPECTION_POLICY = {
    "lot_size": 250,
    "sample_rate": 0.10,
    "min_sample_size": 5,
    "acceptance_rate": 0.06,
    "scrap_rate": 0.30,
    "defect_rate": 0.04,
}

# Used for the second (post-rework) inspection pass. 
REWORK_INSPECTION_POLICY = {
    "lot_size": 250,
    "sample_rate": 0.10,
    "min_sample_size": 5,
    "acceptance_rate": 0.06,
    "defect_rate": 0.01,
}