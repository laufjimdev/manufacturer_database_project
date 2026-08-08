PRODUCT_MATERIALS = {
    1: [  # 60" Round Banquet Table
        (1, 1), 
        (2, 1),
        (11, 1),
        (17, 16),
        (20, 2), #material_id, quantity_required
    ],
    2: [  # 72" Round Banquet Table
        (1, 2),
        (2, 2),
        (11, 1),
        (17, 20),
        (21, 8),
        (20, 3),
        (22, 1),
    ],
    3: [  # 96" Rectangular Conference Table
        (1, 3),
        (2, 3),
        (7, 20),
        (17, 30),
        (21, 12),
        (20, 4),
        (22, 2),
    ],
    4: [  # 6 ft Folding Utility Table
        (3, 1),
        (2, 1),
        (11, 1),
        (17, 18),
        (21, 8),
        (20, 2),
        (22, 1),
    ],
    5: [  # 30" Aluminum Cocktail Table
        (4, 1),
        (6, 10),
        (13, 1),
        (17, 12),
        (20, 1),
        (23, 4),
    ],
    6: [  # Adjustable Aluminum Training Table
        (3, 1),
        (2, 1),
        (5, 16),
        (12, 1),
        (17, 20),
        (18, 12),
        (21, 10),
        (20, 2),
    ],
    7: [  # Portable Aluminum Vendor Table
        (4, 1),
        (5, 14),
        (12, 1),
        (17, 16),
        (18, 10),
        (20, 2),
        (23, 4),
    ],
    8: [  # Aluminum Folding Picnic Table
        (4, 2),
        (5, 24),
        (12, 2),
        (17, 32),
        (18, 20),
        (20, 3),
        (23, 8),
    ],
    9: [  # Heavy-Duty Catering Prep Table
        (9, 1),
        (10, 16),
        (16, 4),
        (19, 1),
        (17, 12),
    ],
    10: [  # Industrial Buffet Serving Table
        (9, 2),
        (10, 24),
        (16, 6),
        (19, 2),
        (17, 24),
        (20, 3),
    ],
    11: [  # Mobile Kitchen Event Table
        (9, 1),
        (10, 18),
        (16, 4),
        (19, 1),
        (17, 16),
        (20, 2),
    ],
    12: [  # Tempered Glass Display Table
        (14, 16),
        (13, 1),
        (8, 8),
        (17, 12),
        (20, 1),
        (23, 4),
    ],
}

# Ratio of each product's quantity relative to product_id 1's quantity
PRODUCT_RATIOS = {
    1: 1.0,
    2: 1.0,
    3: 1.0,
    4: 0.8,
    5: 0.8,
    6: 0.3,
    7: 0.5,
    8: 0.3,
    9: 0.5,
    10: 0.5,
    11: 0.15,
    12: 0.08,
}


def calculate_required_materials(factory_base_quantities: dict) -> dict:
    """
    factory_base_quantities: {"F1": 1000, "F2": 800, "F3": 500}
    Base quantity = quantity of product_id 1 for that factory.
    All other products scale off it via PRODUCT_RATIOS.

    Returns: {"F1": [(material_id, total_qty), ...], ...}
    """
    required_materials = {}

    for factory_id, base_qty in factory_base_quantities.items():
        material_totals = {}

        for product_id, ratio in PRODUCT_RATIOS.items():
            product_qty = round(base_qty * ratio)

            for material_id, qty_per_unit in PRODUCT_MATERIALS[product_id]:
                material_totals[material_id] = (
                    material_totals.get(material_id, 0) + qty_per_unit * product_qty
                )

        required_materials[factory_id] = list(material_totals.items())

    return required_materials
