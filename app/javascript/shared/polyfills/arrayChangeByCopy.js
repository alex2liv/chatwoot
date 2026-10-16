// Metasync: Megatec agents run Chrome 109 on Windows 7 and cannot upgrade.
// Chrome 109 lacks the ES2023 "change array by copy" methods, which
// @chatwoot/viz (reports, CSAT, heatmaps, Captain overview, campaign
// analytics) calls directly. core-js only patches browsers that miss them.
import 'core-js/actual/array/to-sorted';
import 'core-js/actual/array/to-reversed';
import 'core-js/actual/array/to-spliced';
import 'core-js/actual/array/with';
