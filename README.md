# OpenScholarXIV (Android Fork by hydrogen)

> **Note:** This Android-focused fork and its modifications are maintained by **hydrogen**, based on [ScholarXIV/OpenScholarXIV](https://github.com/ScholarXIV/OpenScholarXIV). Currently only the `android` branch is maintained.

OpenScholarXIV is a free and open-source app for finding, reading, bookmarking, summarizing, and discussing arXiv papers with AI.

<div align="center">
  <img src="assets/banners/OpenScholarXIV7.webp" width="700" alt="OpenScholarXIV cover">
</div>

## Modifications by hydrogen

- **Search & Discovery**: Full arXiv category taxonomy with folded category groups, arXiv Advanced Search (`ti:`, `au:`, `abs:`, `co:`, `jr:`, `cat:`, `submittedDate`), arXiv ID/URL quick-jump, and `Newest` sort order by default.
- **Feed & Refresh UX**: Schedule-aware pull-to-refresh matching arXiv's Sun–Thu 20:00 US/Eastern announcement schedule (plus weekend/holiday reminders), folded author lists with expand toggles, and configurable session restore (category-only by default, or full search filter).
- **Paper Details & LaTeX**: Fixed MathJax/LaTeX rendering in abstracts and titles, tap-to-copy abstract/PDF metadata links, and external **References & Citations** jump links (INSPIRE HEP, NASA ADS, Google Scholar, Semantic Scholar).
- **AI & Settings**: Support for both Google Gemini (2.5+) and OpenAI-Compatible providers, organized Appearance and Main Page Style submenus.
- **Android Build & CI**: Migrated to AGP 9.3.1 / Gradle 9.5.0 / Built-in Kotlin, enabled R8 shrinking + WebP banners, and added Android-only GitHub Actions CI (ARM64 & ARMv7 split APKs).

## Features

- Find papers with search and suggested research papers.
- Read papers in-app without leaving OpenScholarXIV.
- Bookmark papers to revisit them later.
- Read and listen to paper summaries.
- Deep dive into papers with AI chat.
- Bring your own Gemini API key.
- Choose between Material You light and dark themes.
- Download and share papers.

## Screens

<div align="center">
  <img src="assets/banners/OpenScholarXIV.webp" width="400" alt="Find papers">
  <img src="assets/banners/OpenScholarXIV2.webp" width="400" alt="Read and listen to summaries">
  <img src="assets/banners/OpenScholarXIV3.webp" width="400" alt="Deep dive with AI">
  <img src="assets/banners/OpenScholarXIV14.jpg" width="400" alt="Chat History">
  <img src="assets/banners/OpenScholarXIV4.webp" width="400" alt="Bring your own keys">
  <!--<img src="assets/banners/OpenScholarXIV5.webp" width="400" alt="Choose themes">-->
  <img src="assets/banners/OpenScholarXIV6.webp" width="400" alt="Read papers in-app">
  <img src="assets/banners/OpenScholarXIV8.webp" width="400" alt="Bookmark papers">
  <img src="assets/banners/OpenScholarXIV10.jpg" width="400" alt="Paper Details">
  <img src="assets/banners/OpenScholarXIV11.jpg" width="400" alt="Paper Notes">
  <img src="assets/banners/OpenScholarXIV12.jpg" width="400" alt="Paper Category">
  <img src="assets/banners/OpenScholarXIV13.jpg" width="400" alt="Search By Author">
  <img src="assets/banners/OpenScholarXIV9.jpg" width="400" alt="Material You Themes">
</div>

## Contributing

Fork the repo, make your changes, and open a pull request. You can also use the issues tab for contribution ideas.

## License

This project is licensed under the GNU General Public License.

## Acknowledgements

Thank you to arXiv for the use of its open access interoperability.

Made by [ScholarXIV](https://ScholarXIV.com).
