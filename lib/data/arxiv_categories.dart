class ArxivCategory {
  const ArxivCategory({
    required this.code,
    required this.label,
    required this.group,
  });

  final String code;
  final String label;
  final String group;

  String get query => "cat:$code";
}

// Kept for backwards compatibility with category parser helpers and tests.
const featuredArxivCategoryCodes = [
  "cs.AI",
  "cs.LG",
  "cs.CV",
  "cs.CL",
  "cs.RO",
  "quant-ph",
  "stat.ML",
  "hep-th",
  "q-bio.NC",
  "eess.AS",
];

const arxivCategories = [
  // Astrophysics
  ArxivCategory(
    code: "astro-ph.CO",
    label: "Cosmology and Nongalactic Astrophysics",
    group: "Astrophysics",
  ),
  ArxivCategory(
    code: "astro-ph.EP",
    label: "Earth and Planetary Astrophysics",
    group: "Astrophysics",
  ),
  ArxivCategory(
    code: "astro-ph.GA",
    label: "Astrophysics of Galaxies",
    group: "Astrophysics",
  ),
  ArxivCategory(
    code: "astro-ph.HE",
    label: "High Energy Astrophysical Phenomena",
    group: "Astrophysics",
  ),
  ArxivCategory(
    code: "astro-ph.IM",
    label: "Instrumentation and Methods for Astrophysics",
    group: "Astrophysics",
  ),
  ArxivCategory(
    code: "astro-ph.SR",
    label: "Solar and Stellar Astrophysics",
    group: "Astrophysics",
  ),

  // Physics
  ArxivCategory(
    code: "gr-qc",
    label: "General Relativity and Quantum Cosmology",
    group: "Physics",
  ),
  ArxivCategory(
    code: "hep-ex",
    label: "High Energy Physics - Experiment",
    group: "Physics",
  ),
  ArxivCategory(
    code: "hep-lat",
    label: "High Energy Physics - Lattice",
    group: "Physics",
  ),
  ArxivCategory(
    code: "hep-ph",
    label: "High Energy Physics - Phenomenology",
    group: "Physics",
  ),
  ArxivCategory(
    code: "hep-th",
    label: "High Energy Physics - Theory",
    group: "Physics",
  ),
  ArxivCategory(
    code: "math-ph",
    label: "Mathematical Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "nucl-ex",
    label: "Nuclear Experiment",
    group: "Physics",
  ),
  ArxivCategory(
    code: "nucl-th",
    label: "Nuclear Theory",
    group: "Physics",
  ),
  ArxivCategory(
    code: "quant-ph",
    label: "Quantum Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.acc-ph",
    label: "Accelerator Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.ao-ph",
    label: "Atmospheric and Oceanic Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.app-ph",
    label: "Applied Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.atm-clus",
    label: "Atomic and Molecular Clusters",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.atom-ph",
    label: "Atomic Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.bio-ph",
    label: "Biological Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.chem-ph",
    label: "Chemical Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.class-ph",
    label: "Classical Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.comp-ph",
    label: "Computational Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.data-an",
    label: "Data Analysis, Statistics and Probability",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.ed-ph",
    label: "Physics Education",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.flu-dyn",
    label: "Fluid Dynamics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.gen-ph",
    label: "General Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.geo-ph",
    label: "Geophysics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.hist-ph",
    label: "History and Philosophy of Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.ins-det",
    label: "Instrumentation and Detectors",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.med-ph",
    label: "Medical Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.optics",
    label: "Optics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.plasm-ph",
    label: "Plasma Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.pop-ph",
    label: "Popular Physics",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.soc-ph",
    label: "Physics and Society",
    group: "Physics",
  ),
  ArxivCategory(
    code: "physics.space-ph",
    label: "Space Physics",
    group: "Physics",
  ),

  // Condensed Matter
  ArxivCategory(
    code: "cond-mat.dis-nn",
    label: "Disordered Systems and Neural Networks",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.mes-hall",
    label: "Mesoscale and Nanoscale Physics",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.mtrl-sci",
    label: "Materials Science",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.other",
    label: "Other Condensed Matter",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.quant-gas",
    label: "Quantum Gases",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.soft",
    label: "Soft Condensed Matter",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.stat-mech",
    label: "Statistical Mechanics",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.str-el",
    label: "Strongly Correlated Electrons",
    group: "Condensed Matter",
  ),
  ArxivCategory(
    code: "cond-mat.supr-con",
    label: "Superconductivity",
    group: "Condensed Matter",
  ),

  // Nonlinear Sciences
  ArxivCategory(
    code: "nlin.AO",
    label: "Adaptation and Self-Organizing Systems",
    group: "Nonlinear Sciences",
  ),
  ArxivCategory(
    code: "nlin.CD",
    label: "Chaotic Dynamics",
    group: "Nonlinear Sciences",
  ),
  ArxivCategory(
    code: "nlin.CG",
    label: "Cellular Automata and Lattice Gases",
    group: "Nonlinear Sciences",
  ),
  ArxivCategory(
    code: "nlin.PS",
    label: "Pattern Formation and Solitons",
    group: "Nonlinear Sciences",
  ),
  ArxivCategory(
    code: "nlin.SI",
    label: "Exactly Solvable and Integrable Systems",
    group: "Nonlinear Sciences",
  ),

  // Computer Science
  ArxivCategory(
    code: "cs.AI",
    label: "Artificial Intelligence",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.AR",
    label: "Hardware Architecture",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.CC",
    label: "Computational Complexity",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.CE",
    label: "Computational Engineering, Finance, and Science",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.CG",
    label: "Computational Geometry",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.CL",
    label: "Computation and Language",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.CR",
    label: "Cryptography and Security",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.CV",
    label: "Computer Vision and Pattern Recognition",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.CY",
    label: "Computers and Society",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.DB",
    label: "Databases",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.DC",
    label: "Distributed, Parallel, and Cluster Computing",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.DL",
    label: "Digital Libraries",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.DM",
    label: "Discrete Mathematics",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.DS",
    label: "Data Structures and Algorithms",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.ET",
    label: "Emerging Technologies",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.FL",
    label: "Formal Languages and Automata Theory",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.GL",
    label: "General Literature",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.GR",
    label: "Graphics",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.GT",
    label: "Computer Science and Game Theory",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.HC",
    label: "Human-Computer Interaction",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.IR",
    label: "Information Retrieval",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.IT",
    label: "Information Theory",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.LG",
    label: "Machine Learning",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.LO",
    label: "Logic in Computer Science",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.MA",
    label: "Multiagent Systems",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.MM",
    label: "Multimedia",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.MS",
    label: "Mathematical Software",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.NA",
    label: "Numerical Analysis",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.NE",
    label: "Neural and Evolutionary Computing",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.NI",
    label: "Networking and Internet Architecture",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.OH",
    label: "Other Computer Science",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.OS",
    label: "Operating Systems",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.PF",
    label: "Performance",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.PL",
    label: "Programming Languages",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.RO",
    label: "Robotics",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.SC",
    label: "Symbolic Computation",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.SD",
    label: "Sound",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.SE",
    label: "Software Engineering",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.SI",
    label: "Social and Information Networks",
    group: "Computer Science",
  ),
  ArxivCategory(
    code: "cs.SY",
    label: "Systems and Control",
    group: "Computer Science",
  ),

  // Mathematics
  ArxivCategory(
    code: "math.AC",
    label: "Commutative Algebra",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.AG",
    label: "Algebraic Geometry",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.AP",
    label: "Analysis of PDEs",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.AT",
    label: "Algebraic Topology",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.CA",
    label: "Classical Analysis and ODEs",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.CO",
    label: "Combinatorics",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.CT",
    label: "Category Theory",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.CV",
    label: "Complex Variables",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.DG",
    label: "Differential Geometry",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.DS",
    label: "Dynamical Systems",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.FA",
    label: "Functional Analysis",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.GM",
    label: "General Mathematics",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.GN",
    label: "General Topology",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.GR",
    label: "Group Theory",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.GT",
    label: "Geometric Topology",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.HO",
    label: "History and Overview",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.IT",
    label: "Information Theory",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.KT",
    label: "K-Theory and Homology",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.LO",
    label: "Logic",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.MG",
    label: "Metric Geometry",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.MP",
    label: "Mathematical Physics",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.NA",
    label: "Numerical Analysis",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.NT",
    label: "Number Theory",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.OA",
    label: "Operator Algebras",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.OC",
    label: "Optimization and Control",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.PR",
    label: "Probability",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.QA",
    label: "Quantum Algebra",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.RA",
    label: "Rings and Algebras",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.RT",
    label: "Representation Theory",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.SG",
    label: "Symplectic Geometry",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.SP",
    label: "Spectral Theory",
    group: "Mathematics",
  ),
  ArxivCategory(
    code: "math.ST",
    label: "Statistics Theory",
    group: "Mathematics",
  ),

  // Statistics
  ArxivCategory(code: "stat.AP", label: "Applications", group: "Statistics"),
  ArxivCategory(code: "stat.CO", label: "Computation", group: "Statistics"),
  ArxivCategory(code: "stat.ME", label: "Methodology", group: "Statistics"),
  ArxivCategory(
    code: "stat.ML",
    label: "Machine Learning",
    group: "Statistics",
  ),
  ArxivCategory(
    code: "stat.OT",
    label: "Other Statistics",
    group: "Statistics",
  ),
  ArxivCategory(
    code: "stat.TH",
    label: "Statistics Theory",
    group: "Statistics",
  ),

  // Electrical Engineering and Systems Science
  ArxivCategory(
    code: "eess.AS",
    label: "Audio and Speech Processing",
    group: "Electrical Engineering",
  ),
  ArxivCategory(
    code: "eess.IV",
    label: "Image and Video Processing",
    group: "Electrical Engineering",
  ),
  ArxivCategory(
    code: "eess.SP",
    label: "Signal Processing",
    group: "Electrical Engineering",
  ),
  ArxivCategory(
    code: "eess.SY",
    label: "Systems and Control",
    group: "Electrical Engineering",
  ),

  // Quantitative Biology
  ArxivCategory(
    code: "q-bio.BM",
    label: "Biomolecules",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.CB",
    label: "Cell Behavior",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.GN",
    label: "Genomics",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.MN",
    label: "Molecular Networks",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.NC",
    label: "Neurons and Cognition",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.OT",
    label: "Other Quantitative Biology",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.PE",
    label: "Populations and Evolution",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.QM",
    label: "Quantitative Methods",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.SC",
    label: "Subcellular Processes",
    group: "Quantitative Biology",
  ),
  ArxivCategory(
    code: "q-bio.TO",
    label: "Tissues and Organs",
    group: "Quantitative Biology",
  ),

  // Quantitative Finance
  ArxivCategory(
    code: "q-fin.CP",
    label: "Computational Finance",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.EC",
    label: "Economics",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.GN",
    label: "General Finance",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.MF",
    label: "Mathematical Finance",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.PM",
    label: "Portfolio Management",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.PR",
    label: "Pricing of Securities",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.RM",
    label: "Risk Management",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.ST",
    label: "Statistical Finance",
    group: "Quantitative Finance",
  ),
  ArxivCategory(
    code: "q-fin.TR",
    label: "Trading and Market Microstructure",
    group: "Quantitative Finance",
  ),

  // Economics
  ArxivCategory(code: "econ.EM", label: "Econometrics", group: "Economics"),
  ArxivCategory(
    code: "econ.GN",
    label: "General Economics",
    group: "Economics",
  ),
  ArxivCategory(
    code: "econ.TH",
    label: "Theoretical Economics",
    group: "Economics",
  ),
];
