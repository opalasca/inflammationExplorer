
library("ggplot2")
library("ggrepel")
library("patchwork")
library("tidyverse")
library("GO.db")
library("org.Hs.eg.db")
library("readxl")
library("clusterProfiler")
library("tidytext")
library("dplyr")
library("stringr")
library("DOSE")
library("fgsea")
library("readxl")
#library("msigdbr")


# Read inflammatome list -------------------------------
data_file <- "data/ranked_list_inflammatome.tsv"
if (file.exists(data_file)) {
  ranked.list <- read_tsv(data_file, show_col_types = FALSE)
} else {
  data_url <- "https://github.com/opalasca/inflammatome_package_sandbox/blob/main/data/ranked_list_inflammatome.tsv"
  data <- read_tsv(data_url, show_col_types = FALSE)
  #stop("Error: Data file not found. Ensure 'data/ranked_list_inflammatome.tsv' exists.")
}

# Convert gene names to Entrez IDs ------
symbol.entrez = bitr(ranked.list$Gene.name, fromType = "SYMBOL", toType = "ENTREZID", OrgDb = org.Hs.eg.db)
ranked.list.entrez.symbol = merge(ranked.list, symbol.entrez, by.x = "Gene.name", by.y = "SYMBOL", all.x = TRUE)

# Get top 2000 genes (inflammatome) and top 100 (inflammation signature) -------
top2000 <- ranked.list.entrez.symbol %>% 
  filter(Position <= 2000)
top100 <- ranked.list.entrez.symbol %>% 
  filter(Position <= 100)



################################################################################
######### Function for GSEA, GSEA dotplot and volcano plot #####################
################################################################################


# Preprocess input file and prepare gene sets for GSEA - not used yet
prepare_data <- function(data, id_col_name, keytype, mean_expr_col_name=NULL, pval_col_name=NULL){
  
  data <- process_input_data(data, id_col_name, keytype, mean_expr_col_name, pval_col_name)
  gene_sets <- get_gene_sets(keytype)
  
  return(list(data, gene_sets))
}


# Preprocess input files  

process_input_data_old <- function(data, id_col_name, keytype) {
  
  # Validate inputs
  if (missing(data) || missing(id_col_name) || missing(keytype)) {
    stop("Missing required inputs")
  }
  
  tryCatch({
    keytype <- tolower(keytype)
    valid_keytypes <- c("uniprot", "symbol", "refseq", "entrez", "ensembl")
    
    if (!keytype %in% valid_keytypes) {
      stop("Invalid keytype provided.")
    }
    
    # Mapping dictionary for keytypes
    keytype_mapping <- list(
      uniprot = "UNIPROT",
      symbol = "SYMBOL",
      refseq = "REFSEQ",
      entrez = "ENTREZID",
      ensembl = "ENSEMBL"
    )
    
    
    # Only assign directly if the dataset already has ENTREZ or ENSEMBL IDs
    if (keytype %in% c("entrez", "ensembl")) {
      if (all(grepl("^ENS", data[[id_col_name]])) && keytype == "ensembl") {
        data$id.mapped <- data[[id_col_name]]
      } else if (all(grepl("^[0-9]+$", data[[id_col_name]])) && keytype == "entrez") {
        data$id.mapped <- data[[id_col_name]]
      } else {
        stop("Selected keytype does not match the dataset. Please choose the correct keytype.")
      }
      return(data)
    }
    
    # Attempt ID conversion
    id.mapping <- clusterProfiler::bitr(
      data[[id_col_name]], 
      fromType = keytype_mapping[[keytype]], 
      toType = "ENTREZID", 
      OrgDb = org.Hs.eg.db
    )
    
    # Merge mapped IDs
    data <- merge(data, id.mapping, by.x = id_col_name, by.y = keytype_mapping[[keytype]], all.x = TRUE)
    
    # Ensure unique ENTREZID, keeping the first sorted entry
    data <- data %>%
      group_by(ENTREZID) %>%
      arrange(!!sym(id_col_name)) %>%
      slice(1) %>%
      ungroup()
    
    # Assign mapped ID column
    data$id.mapped <- data$ENTREZID
    
    return(data)
  }, error = function(e) {
    warning("⚠️ Error in processing identifiers: ", e$message)
    return(NULL)
  })
}

process_input_data <- function(data, id_col_name, keytype) {
  # Validate inputs
  if (missing(data) || missing(id_col_name) || missing(keytype)) {
    stop("Missing required inputs")
  }
  
  tryCatch({
    keytype <- tolower(keytype)
    valid_keytypes <- c("uniprot", "symbol", "refseq", "entrez", "ensembl")
    
    if (!keytype %in% valid_keytypes) {
      stop("Invalid keytype provided.")
    }
    
    keytype_mapping <- list(
      uniprot = "UNIPROT",
      symbol = "SYMBOL",
      refseq = "REFSEQ",
      entrez = "ENTREZID",
      ensembl = "ENSEMBL"
    )
    
    # Direct mapping if ENTREZ or ENSEMBL
    if (keytype %in% c("entrez", "ensembl")) {
      if (keytype == "ensembl" && all(grepl("^ENS", data[[id_col_name]]))) {
        data$id.mapped <- data[[id_col_name]]
      } else if (keytype == "entrez" && all(grepl("^[0-9]+$", data[[id_col_name]]))) {
        data$id.mapped <- data[[id_col_name]]
      } else {
        stop("Selected keytype does not match the dataset. Please choose the correct keytype.")
      }
    } else {
      id.mapping <- clusterProfiler::bitr(
        data[[id_col_name]], 
        fromType = keytype_mapping[[keytype]], 
        toType = "ENTREZID", 
        OrgDb = org.Hs.eg.db
      )
      
      data <- merge(data, id.mapping, by.x = id_col_name, by.y = keytype_mapping[[keytype]], all.x = TRUE)
      data <- data %>%
        group_by(ENTREZID) %>%
        arrange(!!sym(id_col_name)) %>%
        slice(1) %>%
        ungroup()
      data$id.mapped <- data$ENTREZID
    }
    
    # Add inflammatome information
    #reference_data <- if (keytype == "ensembl") ranked.list else ranked.list.entrez.symbol
    #merge_column <- if (keytype == "ensembl") "ENSG.ID" else "ENTREZID"
    
    #data <- left_join(data, reference_data %>% select(!!sym(merge_column), Position), by = c("id.mapped" = merge_column))
    #data$inflammatome.presence <- ifelse(data$Position <= 2000, "yes", "no")
    #data$inflammatome.presence <- ifelse(is.na(data$Position), "no", ifelse(data$Position <= 2000, "yes", "no"))
    #data$inflammatome.rank <- data$Position
    #return(data)
    
    # Add inflammatome information safely
    reference_data <- if (keytype == "ensembl") ranked.list else ranked.list.entrez.symbol
    merge_column <- if (keytype == "ensembl") "ENSG.ID" else "ENTREZID"
    
    # First, remove rows with NA in id.mapped to avoid bad joins
    data_clean <- data %>% filter(!is.na(id.mapped))
    
    # Perform left join only on clean data
    data_clean <- left_join(data_clean, reference_data %>% select(!!sym(merge_column), Position),
                            by = c("id.mapped" = merge_column))
    
    # Reintroduce the rows that had NA id.mapped, keeping them untouched
    data_na <- data %>% filter(is.na(id.mapped)) %>% mutate(Position = NA)
    
    # Combine clean and NA data
    data_final <- bind_rows(data_clean, data_na)
    
    # Set presence flags
    data_final$inflammatome.presence <- ifelse(is.na(data_final$Position), "no",
                                               ifelse(data_final$Position <= 2000, "yes", "no"))
    
    data_final$inflammatome.rank <- data_final$Position
    
    return(data_final)
    
  }, error = function(e) {
    warning("⚠️ Error in processing identifiers: ", e$message)
    return(NULL)
  })
}


# Extract gene sets for GSEA
get_gene_sets <- function(keytype){ 
  
  keytype <- tolower(keytype)
  
  # if the keytype is ensembl, extract gene sets using ensembl ids
  if (keytype == "ensembl") {
    
  go <- msigdbr(species = "Homo sapiens", category = "C5", subcategory = "GO:BP") %>%
    dplyr::filter(gs_exact_source %in% c("GO:0002534", "GO:0006954", "GO:0002526", "GO:0002544")) %>%
    dplyr::select(gs_name, ensembl_gene, gene_symbol, gs_exact_source) %>%
    dplyr::rename(gene = ensembl_gene)
  
  wp <- msigdbr(species = "Homo sapiens", category = "C2", subcategory = "CP:WIKIPATHWAYS") %>%
    dplyr::filter(gs_exact_source %in% c("WP4493", "WP530", "WP5198", "WP453")) %>%
    dplyr::select(gs_name, ensembl_gene, gene_symbol, gs_exact_source) %>%
    dplyr::rename(gene = ensembl_gene)
  
  reactome <- msigdbr(species = "Homo sapiens", category = "C2", subcategory = "CP:REACTOME") %>%
    dplyr::filter(gs_exact_source %in% c("R-HSA-622312", "R-HSA-913531", "R-HSA-9020702", "R-HSA-75893")) %>%
    dplyr::select(gs_name, ensembl_gene, gene_symbol, gs_exact_source) %>%
    dplyr::rename(gene = ensembl_gene)
  
  h <- msigdbr(species = "Homo sapiens", category = "H") %>% 
    dplyr::select(gs_name, ensembl_gene, entrez_gene, gene_symbol)
  
  msigdb.markers <- h[h$gs_name == "HALLMARK_INFLAMMATORY_RESPONSE",]
  #msigdb.markers = msigdb.markers[c(2,3,4)]
  
  top.100 = filter(ranked.list, Position <= 100)$ENSG.ID
  go = dplyr::select(go, gs_name, gene)
  wp = dplyr::select(wp, gs_name, gene)
  reactome = dplyr::select(reactome, gs_name, gene)
  msigdb = msigdb.markers$ensembl_gene
  
  all.sets <- rbind(
    data.frame(gs_name = "Inflammation signature (top100)", gene = top.100) ,
    data.frame(gs_name = "MSigDB hallmark inflammatory response", gene = msigdb),
    go,
    wp,
    reactome
  )
  }
  
  # Use Entrez if the original identifier is not Ensembl
  if (keytype != "ensembl") {
    go <- msigdbr(species = "Homo sapiens", category = "C5", subcategory = "GO:BP") %>%
      dplyr::filter(gs_exact_source %in% c("GO:0002534", "GO:0006954", "GO:0002526", "GO:0002544")) %>%
      dplyr::select(gs_name, entrez_gene, gene_symbol, gs_exact_source) %>%
      dplyr::rename(gene = entrez_gene)
    
    wp <- msigdbr(species = "Homo sapiens", category = "C2", subcategory = "CP:WIKIPATHWAYS") %>%
      dplyr::filter(gs_exact_source %in% c("WP4493", "WP530", "WP5198", "WP453")) %>%
      dplyr::select(gs_name, entrez_gene, gene_symbol, gs_exact_source) %>%
      dplyr::rename(gene = entrez_gene)
    
    reactome <- msigdbr(species = "Homo sapiens", category = "C2", subcategory = "CP:REACTOME") %>%
      dplyr::filter(gs_exact_source %in% c("R-HSA-622312", "R-HSA-913531", "R-HSA-9020702", "R-HSA-75893")) %>%
      dplyr::select(gs_name, entrez_gene, gene_symbol, gs_exact_source) %>%
      dplyr::rename(gene = entrez_gene)
    
    h <- msigdbr(species = "Homo sapiens", category = "H") %>% 
      dplyr::select(gs_name, entrez_gene, entrez_gene, gene_symbol)
    msigdb.markers <- h[h$gs_name == "HALLMARK_INFLAMMATORY_RESPONSE",]
    #msigdb.markers = msigdb.markers[c(2,3,4)]
    
    top.100 = filter(ranked.list.entrez.symbol, Position <= 100)$ENTREZID
    go = dplyr::select(go, gs_name, gene)
    wp = dplyr::select(wp, gs_name, gene)
    reactome = dplyr::select(reactome, gs_name, gene)
    msigdb = msigdb.markers$entrez_gene
    
    all.sets <- rbind(
      data.frame(gs_name = "Inflammation signature (top100)", gene = top.100) ,
      data.frame(gs_name = "MSigDB hallmark inflammatory response", gene = msigdb),
      go,
      wp,
      reactome
    )
  }
  
  return(all.sets)
}


# Run GSEA using cluster profiler 
gsea_analysis_cluster_profiler <- function(data, gene_sets, sorting_value_col_name, name="data"){
  gsea_results <- run_gsea(data, gene_sets, sorting_value_col_name)
  gsea_results_df <- gsea_results@result
  plot_gsea(gsea_results_df, name)
  gsea_results_df=gsea_results_df[-c(10)] # Remove leading_edge column, due to issue when displaying the table
  #gsea_results_df$leading_edge <- gsub("\n", "", gsea_results_df$leading_edge)
  return(gsea_results_df)
}

run_gsea_cluster_profiler <- function(data, gene_sets, sorting_value_col_name) {
  # Filter out rows with NA in id.mapped or sorting column
  data <- data[!is.na(data$id.mapped) & !is.na(data[[sorting_value_col_name]]), ]
  
  # Check if we have any valid data left for GSEA
  if (nrow(data) == 0) {
    stop("No valid data available for GSEA analysis after filtering NAs.")
  }
  
  # Order the data by sorting value column
  data <- data[order(data[[sorting_value_col_name]], decreasing = TRUE), ]
  
  # Create the ranked gene list for GSEA
  ranked_gene_list <- setNames(data[[sorting_value_col_name]], data$id.mapped)
  
  # Run GSEA
  set.seed(100)
  gsea_results <- GSEA(
    ranked_gene_list, 
    TERM2GENE = gene_sets, 
    minGSSize = 0, 
    maxGSSize = 2000, 
    pvalueCutoff = 10,
    eps = 0
  )
  
  return(gsea_results)
}

plot_gsea_cluster_profiler <- function(gsea_result_df, name="data"){
  
  gsea_result_df$Description <- as.character(gsea_result_df$Description)
  gsea_result_df$Description <- gsub("_"," ",gsea_result_df$Description)
  gsea_result_df$Description <- tolower(gsea_result_df$Description)
  gsea_result_df$Description <- sub("^(.)", "\\U\\1", gsea_result_df$Description, perl = TRUE)  # Capitalize first letter
  gsea_result_df$Description <- gsub("Gobp","GOBP",gsea_result_df$Description)
  gsea_result_df$Description <- gsub("Wp","WP",gsea_result_df$Description)
  
  # Wrap text at 32 characters
  gsea_result_df$Description <- str_wrap(gsea_result_df$Description, width = 35)
  
  p <- ggplot(gsea_result_df, aes(x = NES, y = reorder(Description, NES))) + 
    geom_point(aes(fill = NES, size = -log10(p.adjust)), shape = 21, colour = "black", alpha = 0.8) +
    scale_fill_gradient2(midpoint = 0, low = "blue4", mid = "white", high = "red4", space = "Lab") +
    scale_size_continuous(range = c(4, 12)) +  # Increase point size range
    theme_light() + 
    ylab(NULL) + 
    xlab("NES") +
    theme(
      axis.text = element_text(size = 16),    # Increase axis text size
      axis.title = element_text(size = 16),   # Increase axis title size
      plot.title = element_text(size = 16),   # Increase plot title size (if you add a title)
      legend.text = element_text(size = 16),  # Increase legend text size
      legend.title = element_text(size = 16), # Increase legend title size
      strip.text = element_text(size = 16),   # Increase facet text size if using facets
      panel.grid.major = element_line(linewidth = 0.5, linetype = "dashed", colour = "grey90"),
      panel.grid.minor = element_line(linewidth = 0.25, linetype = "dotted", colour = "grey90"),
      plot.margin = margin(10, 10, 10, 10)  # Add some margin around the plot
    )
  
  # Add black dots for p.adjust < 0.05
  p <- p + geom_point(data = gsea_result_df[gsea_result_df$p.adjust < 0.05,], 
                      aes(x = NES, y = Description), 
                      color = "black", size = 1)  # Make these points slightly bigger
  
  # Print the plot
  print(p)
  #ggsave(paste0("figures/gsea_",name,".png"), p, h = 4.5, w = 5.8)
  
}

#igan <- read_tsv("data/test_datasets/02_GSE175759_IgAN_ctl.tsv",show_col_types = FALSE) 
#data <- process_input_data(igan,id="ENSG.ID", keytype="ensembl")
#gene_sets <- get_gene_sets("Ensembl")
#sorting_value_col_name = "stat"

# Run GSEA using fgsea 
gsea_analysis <- function(data, gene_sets, sorting_value_col_name, name="data"){
  gsea_results <- run_gsea(data, gene_sets, sorting_value_col_name)
  plot_gsea(gsea_results, name)
  return(gsea_results)
}

run_gsea <- function(data, gene_sets, sorting_value_col_name) {
  # Remove rows with NA values
  data <- data[!is.na(data$id.mapped) & !is.na(data[[sorting_value_col_name]]), ]
  
  # Check if we have any valid data left for GSEA
  if (nrow(data) == 0) {
    stop("No valid data available for GSEA analysis after filtering NAs.")
  }
  
  # Ensure numeric
  data[[sorting_value_col_name]] <- as.numeric(data[[sorting_value_col_name]])

  # Add small random noise to sorting column to break ties
  data[[sorting_value_col_name]] <- data[[sorting_value_col_name]] + runif(nrow(data), min = 1e-10, max = 1e-8)
  
  # Order the data by sorting value column
  data <- data[order(data[[sorting_value_col_name]], decreasing = TRUE), ]
  
  # Create the ranked gene list
  ranked_gene_list <- setNames(data[[sorting_value_col_name]], data$id.mapped)
  
  # Convert gene sets into the correct format for fgsea
  pathways <- split(gene_sets$gene, gene_sets$gs_name)
  
  # Run fgsea (faster and lower memory usage)
  set.seed(100)
  gsea_results <- fgsea(
    pathways = pathways,
    stats = ranked_gene_list,
    minSize = 1, 
    maxSize = 2000,
    #nperm = 1000 # Reduce permutations if needed to save memory
  )
  
  colnames(gsea_results)[1] <- "Description"
  gsea_results <- gsea_results %>%
    mutate(
      NES = round(NES, 3),
      #pval = round(pval, 6),
      #padj = round(padj, 6),
      log2err = round(log2err, 3),
      ES = round(ES, 3),
    ) %>%
    arrange(desc(NES))
  
  
  gsea_results <- gsea_results %>%
    mutate(Description = case_when(
      Description == "REACTOME_INTERLEUKIN_1_SIGNALING" ~ "REACTOME: IL-1 signaling",                                   
      Description == "GOBP_ACUTE_INFLAMMATORY_RESPONSE" ~ "GOBP: Acute inflammatory response",                                   
      Description == "REACTOME_INTERFERON_SIGNALING" ~ "REACTOME: IFN signaling",                                   
      Description == "WP_INFLAMMATORY_RESPONSE_PATHWAY" ~ "WP: Inflammatory response pathway",                                 
      Description == "Inflammation signature (top100)" ~ "Inflammation signature", 
      Description == "Inflammation signature" ~ "Inflammation signature",                                            
      Description == "MSigDB hallmark inflammatory response" ~ "MSigDB: Hallmark inflammatory response",                             
      Description == "GOBP_INFLAMMATORY_RESPONSE" ~ "GOBP: Inflammatory response",                                         
      Description == "REACTOME_INFLAMMASOMES" ~ "REACTOME: Inflammasomes",                                             
      Description == "WP_CELLS_AND_MOLECULES_INVOLVED_IN_LOCAL_ACUTE_INFLAMMATORY_RESPONSE" ~ "WP: Cells and molecules involved in\nlocal acute inflammatory response",
      Description == "GOBP_CYTOKINE_PRODUCTION_INVOLVED_IN_INFLAMMATORY_RESPONSE" ~ "GOBP: Cytokine production in\ninflammatory response",        
      Description == "REACTOME_TNF_SIGNALING" ~ "REACTOME: TNF signaling",                                            
      Description == "GOBP_CHRONIC_INFLAMMATORY_RESPONSE" ~ "GOBP: Chronic inflammatory response",                                 
      Description == "WP_CYTOKINES_AND_INFLAMMATORY_RESPONSE" ~ "WP: Cytokines and inflammatory response"))
  
  
  return(gsea_results)
}

# Dotplot for GSEA results
plot_gsea <- function(gsea_result_df, name="data"){
  
  gsea_result_df$Description <- as.character(gsea_result_df$Description)
  gsea_result_df$Description <- gsub("_"," ",gsea_result_df$Description)
  gsea_result_df$Description <- tolower(gsea_result_df$Description)
  gsea_result_df$Description <- sub("^(.)", "\\U\\1", gsea_result_df$Description, perl = TRUE)  # Capitalize first letter
  gsea_result_df$Description <- gsub("Gobp","GOBP",gsea_result_df$Description)
  gsea_result_df$Description <- gsub("Wp","WP",gsea_result_df$Description)
  
  # Wrap text at 32 characters
  gsea_result_df$Description <- str_wrap(gsea_result_df$Description, width = 35)
  
  p <- ggplot(gsea_result_df, aes(x = NES, y = reorder(Description, NES))) + 
    geom_point(aes(fill = NES, size = -log10(padj)), shape = 21, colour = "black", alpha = 0.8) +
    scale_fill_gradient2(midpoint = 0, low = "blue4", mid = "white", high = "red4", space = "Lab") +
    scale_size_continuous(range = c(4, 12)) +  # Increase point size range
    theme_light() + 
    ylab(NULL) + 
    xlab("NES") +
    theme(
      axis.text = element_text(size = 16),    # Increase axis text size
      axis.title = element_text(size = 16),   # Increase axis title size
      plot.title = element_text(size = 16),   # Increase plot title size (if you add a title)
      legend.text = element_text(size = 16),  # Increase legend text size
      legend.title = element_text(size = 16), # Increase legend title size
      strip.text = element_text(size = 16),   # Increase facet text size if using facets
      panel.grid.major = element_line(linewidth = 0.5, linetype = "dashed", colour = "grey90"),
      panel.grid.minor = element_line(linewidth = 0.25, linetype = "dotted", colour = "grey90"),
      plot.margin = margin(10, 10, 10, 10)  # Add some margin around the plot
    )
  
  # Add black dots for padj < 0.05
  p <- p + geom_point(data = gsea_result_df[gsea_result_df$padj < 0.05,], 
                      aes(x = NES, y = Description), 
                      color = "black", size = 1)  # Make these points slightly bigger
  
  # Print the plot
  print(p)
  #ggsave(paste0("figures/gsea_",name,".png"), p, h = 4.5, w = 5.8)
  
}


# Volcano plots

plot_volcano <- function(data, keytype="Ensembl", logFC_col_name="log2FoldChange", pval_col_name="pvalue", name="data"){ 
  
  # Define a custom theme with larger text sizes
  theme_custom <- theme_classic() + theme(
    plot.title = element_text(size = 16, face = "bold"),
    axis.title = element_text(size = 16), 
    axis.text = element_text(size = 14), 
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    plot.margin = margin(10, 10, 10, 10)  # Add some margin around the plot
  )
  
  keytype <- tolower(keytype)
  
  # Ensure numeric
  data[[pval_col_name]] <- as.numeric(data[[pval_col_name]])
  data[[logFC_col_name]] <- as.numeric(data[[logFC_col_name]])
  
  if (keytype == "ensembl") {
    data <- data %>%
      arrange(desc(.data[[pval_col_name]])) %>%
      mutate(idx = row_number()) %>%
      mutate(
        top_2000 = if_else(id.mapped %in% filter(top2000, Position <= 2000)$ENSG.ID, "yes", "no"),
        top_100 = if_else(id.mapped %in% filter(top2000, Position <= 100)$ENSG.ID, "yes", "no")
      ) %>%
      mutate(
        top_2000 = factor(top_2000, levels = c("no", "yes")),  # Ensure "no" is plotted first
        top_100 = factor(top_100, levels = c("no", "yes"))
      )  %>%
      mutate(
        # **Cap -log10(p-value) at 20**
        adj_pval = pmin(-log10(.data[[pval_col_name]]), 20),
        # **Cap log fold change between -10 and 10**
        adj_logFC = pmax(pmin(.data[[logFC_col_name]], 10), -10)
      )
  } else {
    data <- data %>%
      arrange(desc(.data[[pval_col_name]])) %>%
      mutate(idx = row_number()) %>%
      mutate(
        top_2000 = if_else(id.mapped %in% filter(top2000, Position <= 2000)$ENTREZID, "yes", "no"),
        top_100 = if_else(id.mapped %in% filter(top2000, Position <= 100)$ENTREZID, "yes", "no")
      ) %>%
      mutate(
        top_2000 = factor(top_2000, levels = c("no", "yes")),  # Ensure "no" is plotted first
        top_100 = factor(top_100, levels = c("no", "yes"))
      )  %>%
      mutate(
        # **Cap -log10(p-value) at 20**
        adj_pval = pmin(-log10(.data[[pval_col_name]]), 20),
        # **Cap log fold change between -10 and 10**
        adj_logFC = pmax(pmin(.data[[logFC_col_name]], 10), -10)
      )
  }
  
  # Volcano plot for top 2000
  p1 <- ggplot(data %>% arrange(top_2000), aes(x = adj_logFC, y = adj_pval, color = top_2000 )) + 
    geom_point(size = 3, alpha = 0.6) +  # Increase point size
    scale_color_manual(name = "Found in gene set", values = c("no" = "grey", "yes" = "red")) +
    labs(
      x = "Log Fold Change",
      y = "-log10(P-Value)",
      title = paste0("Volcano plot of the input dataset with\ninflammatome genes marked in red")
    ) +
    theme_custom + 
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "black", size = 1) +  # Significance line
    geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1)  # Fold-change line
  
  # Save the plot
  print(p1)
  #ggsave(paste0("figures/volcano_2000_", name, ".png"), p1, height = 5, width = 6, dpi = 300)
  
  # Volcano plot for top 100
  p2 <- ggplot(data %>% arrange(top_100), aes(x = adj_logFC, y = adj_pval, color = top_100)) + 
    geom_point(size = 3, alpha = 0.6) +  # Increase point size
    scale_color_manual(name = "Found in gene set", values = c("no" = "grey", "yes" = "red")) +
    labs(
      x = "Log Fold Change",
      y = "-log10(P-Value)",
      title = paste0("Volcano plot of the input dataset with\ninflammation signature genes marked in red")
    ) +
    theme_custom + 
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "black", size = 1) +  # Significance line
    geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1)  # Fold-change line
  
  # Save the plot
  print(p2)
  #ggsave(paste0("figures/volcano_100_", name, ".png"), p2, height = 5, width = 6, dpi = 300)
  
  # Combine both plots (top 2000 and top 100)
  combined_plot <- p1 + p2 + plot_layout(ncol = 2, guides = "collect")
  
  # Print and save the combined plot
  print(combined_plot)
  #ggsave(paste0("figures/volcano_", name, ".png"), combined_plot, height = 5, width = 10, dpi = 300)  # Wider panel for combined plot
}

plot_volcano_2000 <- function(data, keytype = "Ensembl", logFC_col_name = "log2FoldChange", pval_col_name = "pvalue", name = "data") { 
  
  theme_custom <- theme_classic() + theme(
    plot.title = element_text(size = 16, face = "bold"),
    axis.title = element_text(size = 16), 
    axis.text = element_text(size = 14), 
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    plot.margin = margin(10, 10, 10, 10)
  )
  
  keytype <- tolower(keytype)
  
  data[[pval_col_name]] <- as.numeric(data[[pval_col_name]])
  data[[logFC_col_name]] <- as.numeric(data[[logFC_col_name]])
  
  if (keytype == "ensembl") {
    data <- data %>%
      arrange(desc(.data[[pval_col_name]])) %>%
      mutate(idx = row_number()) %>%
      mutate(
        top_2000 = if_else(id.mapped %in% filter(top2000, Position <= 2000)$ENSG.ID, "yes", "no")
      )
  } else {
    data <- data %>%
      arrange(desc(.data[[pval_col_name]])) %>%
      mutate(idx = row_number()) %>%
      mutate(
        top_2000 = if_else(id.mapped %in% filter(top2000, Position <= 2000)$ENTREZID, "yes", "no")
      )
  }
  
  # Convert to factor and apply clipping
  data <- data %>%
    mutate(
      top_2000 = factor(top_2000, levels = c("no", "yes")),
      adj_pval = pmin(-log10(.data[[pval_col_name]]), 20),
      adj_logFC = pmax(pmin(.data[[logFC_col_name]], 10), -10)
    )
  
  # Calculate median logFC ONLY for top 2000 genes
  median_logFC_top2000 <- data %>%
    filter(top_2000 == "yes") %>%
    summarise(median_logFC = median(.data[[logFC_col_name]], na.rm = TRUE)) %>%
    pull(median_logFC)
  
  # Plot
  p1 <- ggplot(data %>% arrange(top_2000), aes(x = adj_logFC, y = adj_pval, color = top_2000)) + 
    geom_point(size = 3, alpha = 0.6) +
    scale_color_manual(name = "Found in gene set", values = c("no" = "grey", "yes" = "red")) +
    labs(
      x = "Log Fold Change",
      y = "-log10(P-Value)",
      title = "Volcano plot of the input dataset with inflammatome genes marked in red"
    ) +
    theme_custom +
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "black", size = 1) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1) +
    geom_vline(xintercept = median_logFC_top2000, linetype = "dotted", color = "red", size = 1)
  
  print(p1)
}

plot_volcano_100 <- function(data, keytype = "Ensembl", logFC_col_name = "log2FoldChange", pval_col_name = "pvalue", name = "data") { 
  
  theme_custom <- theme_classic() + theme(
    plot.title = element_text(size = 16, face = "bold"),
    axis.title = element_text(size = 16), 
    axis.text = element_text(size = 14), 
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 14),
    plot.margin = margin(10, 10, 10, 10)
  )
  
  keytype <- tolower(keytype)
  
  data[[pval_col_name]] <- as.numeric(data[[pval_col_name]])
  data[[logFC_col_name]] <- as.numeric(data[[logFC_col_name]])
  
  if (keytype == "ensembl") {
    data <- data %>%
      arrange(desc(.data[[pval_col_name]])) %>%
      mutate(idx = row_number()) %>%
      mutate(
        top_100 = if_else(id.mapped %in% filter(top100, Position <= 100)$ENSG.ID, "yes", "no")
      )
  } else {
    data <- data %>%
      arrange(desc(.data[[pval_col_name]])) %>%
      mutate(idx = row_number()) %>%
      mutate(
        top_100 = if_else(id.mapped %in% filter(top100, Position <= 100)$ENTREZID, "yes", "no")
      )
  }
  
  # Convert to factor and apply clipping
  data <- data %>%
    mutate(
      top_100 = factor(top_100, levels = c("no", "yes")),
      adj_pval = pmin(-log10(.data[[pval_col_name]]), 20),
      adj_logFC = pmax(pmin(.data[[logFC_col_name]], 10), -10)
    )
  
  # Calculate median logFC ONLY for top 100 genes
  median_logFC_top100 <- data %>%
    filter(top_100 == "yes") %>%
    summarise(median_logFC = median(.data[[logFC_col_name]], na.rm = TRUE)) %>%
    pull(median_logFC)
  
  # Plot
  p1 <- ggplot(data %>% arrange(top_100), aes(x = adj_logFC, y = adj_pval, color = top_100)) + 
    geom_point(size = 3, alpha = 0.6) +
    scale_color_manual(name = "Found in gene set", values = c("no" = "grey", "yes" = "red")) +
    labs(
      x = "Log Fold Change",
      y = "-log10(P-Value)",
      title = "Volcano plot of the input dataset with inflammation signature genes marked in red"
    ) +
    theme_custom +
    geom_hline(yintercept = -log10(0.05), linetype = "dashed", color = "black", size = 1) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "black", size = 1) +
    geom_vline(xintercept = median_logFC_top100, linetype = "dotted", color = "red", size = 1)
  
  print(p1)
}

#data=data;logFC_col_name = "logFC";pval_col_name = "P.Value";keytype="Entrez";name="data"
#x=data[data$top_2000=="yes",]
#x=x[x$logFC>0,]
#hist(x$logFC, breaks=100)