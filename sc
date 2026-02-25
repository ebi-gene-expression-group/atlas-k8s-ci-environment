<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="utf-8">
    <title>Home &lt; Single Cell Expression Atlas &lt; EMBL-EBI</title>
    <meta name="description" content="EMBL-EBI Single Cell Expression Atlas, an open public repository of single cell gene expression data">
    <meta name="keywords" content="expression atlas, single cell expression, gene expression, baseline expression, functional genomics, public repository, repository, bioinformatics, europe, institute">
    <meta name="author" content="EBI Functional Genomics Team – https://www.ebi.ac.uk/people/person/christina-ernst">
    <meta name="HandheldFriendly" content="true" />
    <meta name="MobileOptimized" content="width" />
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="theme-color" content="#70BDBD"> <!-- Android Chrome mobile browser tab color -->

    <!-- Add information on the life cycle of this page -->
    <meta name="ebi:owner" content="Christina Ernst <cernst@ebi.ac.uk>">

    <!-- If you link to any other sites frequently, consider optimising performance with a DNS prefetch -->
    <link rel="dns-prefetch" href="https://ebi.emblstatic.net/">
    <link rel="dns-prefetch" href="https://embl.de/">

    <!-- If you have custom icon, replace these as appropriate. You can generate them at realfavicongenerator.net -->
    <link rel="icon" type="image/x-icon" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/favicon.ico" />
    <link rel="icon" type="image/png" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/favicon-32x32.png" />
    <link rel="icon" type="image/png" sizes="192×192" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/android-chrome-192x192.png" /> <!-- Android (192px) -->
    <link rel="apple-touch-icon-precomposed" sizes="114x114" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/apple-icon-114x114.png" /> <!-- For iPhone 4 Retina display (114px) -->
    <link rel="apple-touch-icon-precomposed" sizes="72x72" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/apple-icon-72x72.png" /> <!-- For iPad (72px) -->
    <link rel="apple-touch-icon-precomposed" sizes="144x144" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/apple-icon-144x144.png" /> <!-- For iPad retina (144px) -->
    <link rel="apple-touch-icon-precomposed" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/apple-icon-57x57.png" /> <!-- For iPhone (57px) -->
    <link rel="mask-icon" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/safari-pinned-tab.svg" color="#ffffff" /> <!-- Safari icon for pinned tab -->
    <meta name="msapplication-TileColor" content="#2b5797" /> <!-- MS Icons -->
    <meta name="msapplication-TileImage" content="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/images/logos/EMBL-EBI/favicons/mstile-144x144.png" />

    <!-- CSS: implied media=all -->
    <!-- CSS concatenated and minified via ant build script-->
    <link rel="stylesheet" href="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/css/ebi-global.css" type="text/css" media="all" />
    <link rel="stylesheet" href="https://ebi.emblstatic.net/web_guidelines/EBI-Icon-fonts/v1.3/fonts.css" type="text/css" media="all" />

    <!-- If you have a custom header image or colour -->
    <meta name="ebi:masthead-color" content="rgb(0,124,130)" />
    <meta name="ebi:masthead-image" content="/gxa/sc/resources/images/cells_background.png" />

    <!-- you can replace this with theme-[projectname].css. See http://www.ebi.ac.uk/web/style/colour for details of how to do this -->
    <!-- also inform ES so we can host your colour palette file -->
    <!-- <link rel="stylesheet" href="https://dev.ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/css/theme-embl-petrol.css" type="text/css" media="all" /> -->
    <link rel="stylesheet" href="/gxa/sc/resources/css/atlas.css" type="text/css" media="all">

    <!-- Use this CSS file for any custom styling -->
    <link rel="stylesheet" href="/gxa/sc/resources/css/theme-atlas.css" type="text/css" media="all">
    <!-- end CSS-->

</head>

<body>
<div id="skip-to">
    <ul>
        <li><a href="#content">Skip to main content</a></li>
        <li><a href="#local-nav">Skip to local navigation</a></li>
        <li><a href="#global-nav">Skip to EBI global navigation menu</a></li>
        <li><a href="#global-nav-expanded">Skip to expanded EBI global navigation menu (includes all sub-sections)</a></li>
    </ul>
</div>

<header id="masthead-black-bar" class="clearfix masthead-black-bar">
    <script>
        // Hack that solves https://github.com/ebiwd/EBI-Framework/pull/139 (I got tired of waiting)
        window.addEventListener('load', function() {
            $('#masthead-black-bar nav')[2].className='row expanded';
        });
    </script>
</header>
<div>
    <div class="row-expanded callout-background">
        <div id="information-banner" class="columns small-8 small-centered margin-bottom-none text-large"></div>
    </div>

    <div data-sticky-container>
        <header id="masthead" class="masthead" data-sticky data-sticky-on="large" data-top-anchor="content:top" data-btm-anchor="content:bottom">
            <div class="masthead-inner row expanded">
                <div class="small-12 large-8 columns">
                    <a href="/gxa/sc/" title="Back to Single Cell Expression Atlas homepage">
                        <div class="media-object" id="local-title">
                            <div class="media-object-section hide-for-small-only">
                                <img src="/gxa/sc/resources/images/logos/sc_atlas_logo.png" alt="Single Cell Expression Atlas logo" style="height: 7em">
                            </div>
                            <div class="media-object-section">
                                <h1>Single Cell Expression Atlas</h1>
                                <h4 class="show-for-large">Single cell gene expression across species</h4>
                            </div>
                        </div>
                    </a>
                </div>
                <div class="small-12 large-4 columns">
                    <div class="media-object" style="display: flex; justify-content: flex-end; align-items: center;">
                        <div class="media-object-section">
                            <h4 class="show-for-large">Query bulk expression</h4>
                            <a href="/gxa" title="To Expression Atlas" class="button" style="box-shadow: 2px 2px 2px 2px rgba(0,0,0,0.5)"><i class="icon icon-functional" data-icon="<"></i> Back to Expression Atlas</a>
                        </div>
                        <div class="media-object-section show-for-large">
                            <a href="https://wellcome.ac.uk/">
                                <img src="/gxa/sc/resources/images/logos/wellcome_trust_logo_black.png" alt="Wellcome Trust logo" style="max-height: 5.5em; background: white">
                            </a>
                        </div>
                    </div>
                </div>

                <nav>
                    <ul id="local-nav" class="dropdown menu float-left" data-description="navigational">
                        <li id="local-nav-home"><a href="/gxa/sc/home"><i class="icon icon-generic padding-right-medium" data-icon="H"></i>Home</a></li>
                        <li id="local-nav-experiments"><a href="/gxa/sc/experiments"><i class="icon icon-functional padding-right-medium" data-icon="C"></i>Browse experiments</a></li>
                        <li id="local-nav-download"><a href="/gxa/sc/download"><i class="icon icon-functional padding-right-medium" data-icon="="></i>Download</a></li>
                        <li id="local-nav-release-notes"><a href="/gxa/sc/release-notes.html"><i class="icon icon-generic padding-right-medium" data-icon=";"></i>Release notes</a></li>
                        <li id="local-nav-help"><a href="/gxa/sc/help.html?section=null"><i class="icon icon-generic padding-right-medium" data-icon="?"></i>Help</a></li>
                        <li id="local-nav-feedback"><a href="https://www.ebi.ac.uk/support/gxasc" target="_blank" data-icon="X"><i class="icon icon-generic padding-right-medium" data-icon="s"></i>Support</a></li>
                    </ul>
                </nav>
            </div>
        </header>
    </div>
</div>

<div id="content">
    <section id="main-content-area" class="margin-top-large margin-bottom-large" role="main">
        <div class="row expanded">
    <div>
  <div class="small-12 medium-6 columns text-left">
    <h4>
      <small>
        Search across <strong><span>1</span>&nbsp;species</strong>,
        <strong><span>7</span>&nbsp;studies</strong>,
        <strong>
          <span>8,932</span>
          <span>cells</span>
        </strong>
      </small>
    </h4>
  </div>
  <div class="small-12 medium-6 columns hide-for-small-only text-right">
    <h4>
      <small>
        Ensembl&nbsp;<span>104</span>,
        Ensembl&nbsp;Genomes&nbsp;<span>51</span>,
        WormBase&nbsp;ParaSite&nbsp;<span>15</span>,
        EFO&nbsp;<span>3.10.0</span>
      </small>
    </h4>
  </div>
</div>

</div>

<div class="row column margin-bottom-xlarge expanded">
    <ul class="tabs" data-tabs id="search-tabs">
    <li class="tabs-title is-active"><a href="#search-atlas" aria-selected="true">Search</a></li>
</ul>

<div class="tabs-content" data-tabs-content="search-tabs">
    <div class="tabs-panel is-active " id="search-atlas" style="background-color: #e6e6e6;">
        <div id="search-form"></div>
    </div>
</div>

<script defer src="/gxa/sc/resources/js-bundles/geneSearchForm.bundle.js"></script>
<script>
    const contextPath = "\/gxa\/sc\/";
    document.addEventListener("DOMContentLoaded", function () {
        geneSearchForm.render({
            host: contextPath,
            resource: 'json/suggestions/species',
            defaultSpecies: ``,
            wrapperClassName: 'row expanded',
            actionEndpoint: 'search',

            autocompleteClassName: 'small-12 medium-8 columns',
            suggesterEndpoint: 'json/suggestions/gene_ids',

            enableSpeciesSelect: true,
            speciesSelectClassName: 'small-12 medium-4 columns',

            autocompleteLabel: '',
            searchExamples: [
                {
                    text: 'CFTR (gene symbol)',
                    url: contextPath + 'search?symbol=CFTR'
                },
                {
                    text: 'ENSG00000125798 (Ensembl ID)',
                    url: contextPath + 'search?ensgene=ENSG00000125798'
                },
                {
                    text: '657 (Entrez ID)',
                    url: contextPath + 'search?entrezgene=657'
                },
                {
                    text: 'MGI:98354 (MGI ID)',
                    url: contextPath + 'search?mgi_id=MGI:98354'
                },
                {
                    text: 'FBgn0003062 (FlyBase ID)',
                    url: contextPath + 'search?flybase_gene_id=FBgn0003062'
                },
                {
                    text: 'keratinocyte (cell type)',
                    url: contextPath + 'search/metadata/keratinocyte'
                },
                {
                    text: 'liver (organ/organism part)',
                    url: contextPath + 'search/metadata/liver'
                },
                {
                    text: 'lung cancer (disease/condition)',
                    url: contextPath + 'search/metadata/lung cancer'
                }
            ]
        }, 'search-form')
    });
</script>

</div>

<div class="row column margin-bottom-xlarge expanded">
    <div id="species-summary-panel"></div>

<div class="row expanded column text-center margin-top-medium">
  <a class="button primary" href="/gxa/sc/experiments">Show experiments of all species</a>
</div>

<script defer src="/gxa/sc/resources/js-bundles/homepageSpeciesSummaryPanel.bundle.js"></script>

<script>
  document.addEventListener('DOMContentLoaded', function() {
    var sliderSettings = {
      dots: true,
      infinite: false,
      speed: 500,
      slidesToShow: 6,
      slidesToScroll: 6,
      adaptiveHeight: true,
      autoplay: false,
      autoplaySpeed: 2000,
      responsive: [
        {
          breakpoint: 1024,
          settings: {
            slidesToShow: 3,
            slidesToScroll: 3,
            infinite: true,
            dots: true
          }
        },
        {
          breakpoint: 600,
          settings: {
            slidesToShow: 2,
            slidesToScroll: 2,
            dots: true
          }
        },
        {
          breakpoint: 480,
          settings: {
            slidesToShow: 1,
            slidesToScroll: 1,
            dots: true
          }
        }
      ]
    };

    homepageSpeciesSummaryPanel.render({
        host: '$contextPath',
        resource: 'json/species-summary?limit=100',
        carouselCardsRowProps: {
          className: 'row expanded small-up-2 medium-up-3 large-up-6',
          cardContainerClassName: 'column',
          sliderSettings: sliderSettings,
          containerHeight: '320px',
          sliderHeight: '300px'
        },
        onComponentDidMount: function() {
          $('#species-summary-panel').foundation();
          $('#species-summary-panel').foundationExtendEBI();
        }
      },
      'species-summary-panel');
  })
</script>

</div>

<div class="row column margin-bottom-xlarge expanded">
    <div id="experiments-summary-panel"></div>

<script defer src="/gxa/sc/resources/js-bundles/homepageExperimentsSummaryPanel.bundle.js"></script>

<script>
  document.addEventListener('DOMContentLoaded', function() {
    homepageExperimentsSummaryPanel.render(
      {
        host: '$$contextPath',
        resource: 'json/experiments-summary',
        responsiveCardsRowProps: {
          className: 'row expanded small-up-2 medium-up-3 large-up-6',
          cardContainerClassName: 'column',
          imageIconHeight: '3rem'
        },
        onComponentDidMount: function() {
          $('#experiments-summary-panel').foundation();
          $('#experiments-summary-panel').foundationExtendEBI();
        }
      },
      'experiments-summary-panel');
  });
</script>


</div>

<div class="row expanded margin-top-large" data-equalizer>
    <div class="small-12 medium-12 large-6 columns">
        <div id="tools" class="callout" data-equalizer-watch>
    <h4>Tools</h4>

    <a href="https://github.com/ebi-gene-expression-group/scxa-workflows/tree/0.1.0" target="_blank">
        <div class="media-object">
            <div class="media-object-section middle">
                <h3 class="icon icon-generic" data-icon=":"></h3>
            </div>
            <div class="media-object-section middle">
                <p>
                    <strong>SCXA-Workflows</strong><br>
                    A flexible pipeline for Single Cell RNA-seq analysis that integrates many existing tools for
                    filtering and mapping reads, quantifying expression, clustering, finding marker genes and variable
                    genes. The workflows maximize reproducibility by making use of Bioconda, Biocontainers, NextFlow
                    and Galaxy. They can be run on the cloud, local machines or local premises.
                </p>
            </div>
        </div>
    </a>

    <a href="https://github.com/ebi-gene-expression-group/atlas-components/tree/master/packages/scxa-tsne-widget" target="_blank">
        <div class="media-object">
            <div class="media-object-section middle">
                <h3 class="icon icon-conceptual" data-icon="g"></h3>
            </div>
            <div class="media-object-section middle">
                <p>
                    <strong>Single Cell Expression Atlas t-SNE plot widget</strong><br>
                    You can embed the Single Cell Expression Atlas t-SNE plots as a JavaScript widget on your site.
                    There are detailed instructions to integrate the plots in your service in the linked GitHub
                    repository.
                </p>
            </div>
        </div>
    </a>

</div>

    </div>
    <div class="small-12 medium-12 large-6 columns">
        <div id="publication-list" class="callout" data-equalizer-watch>
    <h4>Publications </h4>
    <a href="https://doi.org/10.1093/nar/gkad1021" target="_blank">
        <div class="media-object">
            <div class="media-object-section middle">
                <h3 class="icon icon-conceptual" data-icon="l"></h3>
            </div>
            <div class="media-object-section middle">
                <p>
                    <strong>Expression Atlas update: insights from sequencing data at both bulk and single cell level</strong>
                    <br>
                    <em>Nucleic Acids Research</em>, 22 November 2023.
                </p>
            </div>
        </div>
    </a>
    <a href="https://academic.oup.com/nar/article/50/D1/D129/6438036" target="_blank">
        <div class="media-object">
            <div class="media-object-section middle">
                <h3 class="icon icon-conceptual" data-icon="l"></h3>
            </div>
            <div class="media-object-section middle">
                <p>
                    <strong>Expression Atlas update: gene and protein expression in multiple species</strong><br>
                    <em>Nucleic Acids Research</em>, 24 November 2021.
                </p>
            </div>
        </div>
    </a>
    <a href="https://www.nature.com/articles/s41592-021-01102-w" target="_blank">
        <div class="media-object">
            <div class="media-object-section middle">
                <h3 class="icon icon-conceptual" data-icon="l"></h3>
            </div>
            <div class="media-object-section middle">
                <p>
                    <strong>User-friendly, scalable tools and workflows for single-cell RNA-seq analysis</strong>
                    <br>
                    <em>Nature Methods</em>, 29 March 2021.
                </p>
            </div>
        </div>
    </a>
</div>
    </div>
</div>

<script>
    document.addEventListener("DOMContentLoaded", function() {
        document.getElementById("local-nav-home").className += ' active';
    });
</script>

    </section>
    <footer id="local-footer" class="local-footer" role="local-footer">
    <div id="relationships" class="row">
        <!-- https://www.ebi.ac.uk/style-lab/websites/patterns/banner-elixir.html -->
        <div class="small-10 columns">
            <div id="elixir-banner"
                 data-color="none"
                 data-use-cdr-logo="false"
                 data-name="This service"
                 data-description="Expression Atlas is an ELIXIR database service"
                 data-more-information-link="https://www.elixir-europe.org/about-us/who-we-are/nodes/embl-ebi"
                 data-use-basic-styles="false">
            </div>
        </div>
        <div class="small-2 columns text-right padding-top-medium">
            <a href="https://wellcome.ac.uk/" class="clear">
                <img src="/gxa/sc/resources/images/logos/wellcome_trust_logo_black.png"
                     alt="Wellcome Trust logo" style="height: 4em">
            </a>
        </div>
    </div>

    <script defer="defer" src="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/js/elixirBanner.js"></script>
</footer>
</div>

<footer>
    <div id="global-footer" class="global-footer">
        <nav id="global-nav-expanded" class="global-nav row">
        </nav>
        <section id="ebi-footer-meta" class="ebi-footer-meta row">
        </section>
    </div>
</footer>

<!-- jQuery -->
<script src="https://code.jquery.com/jquery-2.2.4.min.js"></script>
<script src="https://code.jquery.com/jquery-migrate-1.4.1.min.js"></script>

<!-- Don’t defer or async, these two need to be loaded before other bundles, which are effectively deferred -->
<script src="/gxa/sc/resources/js/lib/babel-polyfill.min.js"></script>
<script src="/gxa/sc/resources/js/lib/fetch-polyfill.min.js"></script>
<script src="/gxa/sc/resources/js/lib/url-search-params-polyfill.min.js"></script>
<script src="/gxa/sc/resources/js/lib/append-polyfill.min.js"></script>
<script src="/gxa/sc/resources/js-bundles/vendorCommons.bundle.js"></script>
<script src="/gxa/sc/resources/js-bundles/informationBanner.bundle.js"></script>

<!-- JavaScript -->
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.10.2/jquery.min.js"></script>
<script defer="defer" src="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/js/script.js"></script>

<!-- The Foundation theme JavaScript -->
<script src="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/libraries/foundation-6/js/foundation.js"></script>
<script src="https://ebi.emblstatic.net/web_guidelines/EBI-Framework/v1.3/js/foundationExtendEBI.js"></script>
<script type="text/javascript">$(document).foundation();</script>
<script type="text/javascript">$(document).foundationExtendEBI();</script>
<!-- end CSS-->

<!-- Google Analytics -->
<script>
    window.ga=window.ga||function(){(ga.q=ga.q||[]).push(arguments)};ga.l=+new Date;
    ga('create', 'UA-37676851-3', 'auto');
    ga('send', 'pageview');
</script>
<script async src="https://www.google-analytics.com/analytics.js"></script>
<!-- End Google Analytics -->

<!-- Display an optional informative message for our users -->
<script>informationBanner.render({}, 'information-banner');</script>

</body>
</html>