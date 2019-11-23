VERSION <- "1.1"

cat("Non-Parametric Shrinkage", VERSION, "\n")

ASSERT <- function(test) {
    if (length(test) == 0) {
        stop(paste("ASSERT fail for empty conditional:",
                   deparse(substitute(test))))
    }

    if (is.na(test)) {
        stop(paste("ASSERT fail for missing value:",
                   deparse(substitute(test))))
    }
    
    if (!test) {
        stop(paste("ASSERT fail:", deparse(substitute(test))))
    }
}

#########################################################################

cargs <- commandArgs(trailingOnly=TRUE)

if (length(cargs) < 1) {    
    stop("Usage: Rscript nps_reweight.R <work dir> [<WINSHIFT> ...]")
}

tempprefix <- paste(cargs[1], "/", sep='')

# Read in saved settings
args <- readRDS(paste(tempprefix, "args.RDS", sep=''))

summstatfile <- args[["summstatfile"]] 
traindir <- args[["traindir"]]
trainfreqfile <- args[["trainfreqfile"]]
traintag <- args[["traintag"]]
trainfamfile <- args[["trainfamfile"]]
trainphenofile <- args[["trainphenofile"]]
WINSZ <- args[["WINSZ"]]


if (length(cargs) > 1) {

    WINSHIFT.list <- as.numeric(cargs[2:length(cargs)])

} else {

    cat("Detecting window shifts :")

    part.files <- list.files(tempprefix, pattern="*.part.RDS")
        
    WINSHIFT.list <-
        sapply(part.files,
               function (s) strsplit(s, ".", fixed=TRUE)[[1]][1],
               simplify=TRUE)

    WINSHIFT.list <-
        sapply(WINSHIFT.list,
               function (s) strsplit(s, "_", fixed=TRUE)[[1]][2],
               simplify=TRUE)

    WINSHIFT.list <- sort(as.numeric(WINSHIFT.list))

    cat(paste(WINSHIFT.list, collapse=" "), "\n")
}

if (any(is.nan(WINSHIFT.list)) || any(WINSHIFT.list < 0) ||
    any(WINSHIFT.list >= WINSZ)) {
    
    if (length(cargs) > 1) {
        stop("Invalid shift (window size =", WINSZ, "):",
             cargs[2:length(cargs)])
    } else {
        stop("Invalid shift (window size =", WINSZ, "):",
             WINSHIFT.list)
    }
}

#########################################################################

for (WINSHIFT in WINSHIFT.list) {

    cat("----- Shifted by", WINSHIFT, "-----\n")


    ## Load partition data 
    part <- readRDS(paste(tempprefix, "win_", WINSHIFT, ".part.RDS", sep=''))

    Nt <- part[["Nt"]]
    nLambdaPT <- part[["nLambdaPT"]]
    nEtaPT <- part[["nEtaPT"]]
    lambda.q <- part[["lambda.q"]]
    betahatH.q <- part[["betahatH.q"]]

#########################################################################

    cat("train fam file:", trainfamfile, "\n")
    cat("train pheno file:", trainphenofile, "\n")
    cat("Size of training cohort:", Nt, "\n")
    
    ## phenotypes
    trfam <- read.delim(trainfamfile, sep=" ", header=FALSE,
                        stringsAsFactors=FALSE)
    trphen <- read.delim(trainphenofile, sep="\t", header=TRUE,
                         stringsAsFactors=FALSE)

    if (ncol(trfam) != 6) {
        ## re-try with tab delimination

        trfam <- read.delim(trainfamfile, sep="\t", header=FALSE,
                            stringsAsFactors=FALSE)
    }

    ASSERT(ncol(trfam) == 6)
    
    rownames(trphen) <- paste(trphen$FID, trphen$IID, sep=":")
    trphen <- trphen[paste(trfam[, 1], trfam[, 2], sep=":"), ]


# print(length(intersect(paste(trfam[, 1], trfam[, 2], sep=":"),
#                        paste(trphen$FID, trphen$IID, sep=":")
#                        )))
# print(sum(is.na(trphen$Outcome)))

    ASSERT(all(!is.na(trphen$Outcome)))
    ASSERT(all(trphen$FID == trfam[, 1]))
    ASSERT(all(trphen$IID == trfam[, 2]))

    trY <- trphen$Outcome

    ASSERT(Nt == length(trY))

    if (any(trY == -9)) {
        stop("Missing outcome (\"-9\") is not allowed")
    }

    use.lda <- TRUE

    if (length(unique(trphen$Outcome)) > 2) {
        ## Quantitative phenotypes
        cat("Quantitative phenotype: Outcome - ")

        use.lda <- FALSE
        
        if (!is.numeric(trphen$Outcome)) {
            stop("phenotype values are not numeric: Outcome :", trainphenofile)
        }
    
    } else {
        ## Binary phenotypes    
        cat("Binary phenotype: Outcome - ")

        use.lda <- TRUE

        if (length(setdiff(trphen$Outcome, c(0, 1))) != 0) {
            print(head(trphen[!(trphen$Outcome %in% c(0, 1)), ]))
            stop("Only 0 or 1 is expected in Outcome:", trainphenofile)
        }

        if (sum(trphen$Outcome == 0) == 0) {
            stop("Must have controls (Outcome = 0):", trainphenofile)
        }

        if (sum(trphen$Outcome == 1) == 0) {
            stop("Must have cases (Outcome = 1):", trainphenofile)
        }
    }

    if (use.lda) {
        cat("Using linear discriminary analysis...\n")
    } else {
        cat("Using linear regression...\n")
    }

#########################################################################
## Read partitions

    trPT <- array(0, dim=c(Nt, nLambdaPT, nEtaPT, 1))    

    for (chrom in 1:22) {

        trPT.chr <-
            readRDS(paste(tempprefix, "win_", WINSHIFT, ".trPT.", chrom,
                          ".RDS", sep=''))

        trPT <- trPT + trPT.chr
    }

#########################################################################

    PTwt <- array(0, dim=c(nLambdaPT, nEtaPT, 1))

    for (I in 1:nLambdaPT) {
        for (J in 1:nEtaPT) {
            K <- 1
        
            if (use.lda) {
                
                trcaVAR <- var(trPT[trY == 1, I, J, K])
                trctVAR <- var(trPT[trY == 0, I, J, K])
                trptVAR <- (trcaVAR + trctVAR) / 2
        
                trcaMU <- mean(trPT[trY == 1, I, J, K])
                trctMU <- mean(trPT[trY == 0, I, J, K])
                
                PTwt[I, J, K] <- (trcaMU - trctMU) / trptVAR

            } else {
                ## Use linear regression 
                x <- trPT[, I, J, K]
                
                trlm <- lm(trY ~ x)
                PTwt[I, J, K] <- trlm$coefficients[2]
            }
        }
    }


    if (any(is.nan(PTwt))) {
        cat("WARNING: ", sum(is.nan(PTwt)), "partitions produced NaN\n")
    }

# cat(PTwt[ , , 1])

    PTwt[is.nan(PTwt)] <- 0

    cat("Saving ", nLambdaPT, "x", nEtaPT, "partition weights...")

    saveRDS(PTwt, paste(tempprefix, "win_", WINSHIFT, ".PTwt.RDS", sep=''))

    cat("OK\n")

#########################################################################

    ## tail partition
    trPT.tail <- rep(0, Nt)

    for (chrom in 1:22) {
    
        trPT.tail.file <-
            paste(tempprefix, "trPT.", chrom, ".tail.RDS", sep='')
        
        if (file.exists(trPT.tail.file)) {
        
            cat("Loading S0 partition for chrom", chrom, "...\n")

            trPT.tail.chr <- readRDS(trPT.tail.file)
            
            trPT.tail <- trPT.tail + trPT.tail.chr
        }
    }

    PTwt.tail <- 0
    
    if (any(trPT.tail != 0)) {
        
        if (use.lda) {
            
            trcaVAR <- var(trPT.tail[trY == 1])
            trctVAR <- var(trPT.tail[trY == 0])
            trptVAR <- (trcaVAR + trctVAR) / 2
            
            trcaMU <- mean(trPT.tail[trY == 1])
            trctMU <- mean(trPT.tail[trY == 0])
            
            PTwt.tail <- (trcaMU - trctMU) / trptVAR

        } else {
            ## Use linear regression 
            x <- trPT.tail
            
            trlm <- lm(trY ~ x)
            PTwt.tail <- trlm$coefficients[2]
        }
    }

#    cat("Weight for S0 =", PTwt.tail, "\n")

    if (WINSHIFT == 0) {

        cat("Saving S0 weight...")
    
        saveRDS(PTwt.tail, paste(tempprefix, "PTwt.tail.RDS", sep=''))

        cat("OK\n")
    } 
    
######################################################################
## Training R2

    predY0 <- rep(0, Nt)

    for (I in 1:nLambdaPT) {
        for (J in 1:nEtaPT) {
            K <- 1

            predY0 <- predY0 + PTwt[I, J, K] * trPT[, I, J, K]

        }
    }
    
    predY0 <- predY0 + PTwt.tail * trPT.tail 

    cat("Observed scale R2 in training =", cor(trY, predY0)**2, "\n")

#########################################################################
## back2snpeff

    for (CHR in 1:22) {

        cat("Re-weighting SNPs in chr", CHR, "...\n")

    ## Read summary stats (discovery)
        summstat.chr <- read.delim(paste(summstatfile, ".", CHR, sep=''),
                                   header=TRUE, stringsAsFactors=FALSE,
                                   sep="\t")
        #dim(summstat)

        ## Use traing AF instead of discovery AF
        trfrq.chr <-
            read.table(paste(trainfreqfile, ".", CHR, sep=''), header=TRUE)
        tr.se.chr <- sqrt(2 * trfrq.chr$AAF * (1 - trfrq.chr$AAF))
        #plot(tr.se, se, cex=0.25)
        #abline(0, 1, col="red")

        M.chr <- length(tr.se.chr)

        ASSERT(M.chr == nrow(summstat.chr))

        cat("M", "CHR", CHR, "=", M.chr, "\n")

        wt.betahat <- c()

        I <- 1

        winfilepre <-
            paste(tempprefix, "win_", WINSHIFT, ".", CHR, ".", I, sep='')
        
        while (file.exists(paste(winfilepre, ".pruned", ".table", sep=''))) {

            tailfixfile <- paste(winfilepre, ".pruned", ".table", sep='')
            
            wintab <- read.delim(tailfixfile, header=TRUE, sep="\t")
    
            lambda0 <- wintab$lambda
            etahat0 <- wintab$etahat
            
            Q0 <- readRDS(paste(winfilepre, ".Q.RDS", sep=''))
            
            etahat0 <- etahat0[lambda0 > 0]
            Q0 <- Q0[, lambda0 > 0, drop=FALSE]
            lambda0 <- lambda0[lambda0 > 0]

            Nq <- length(etahat0)
            
            if (Nq == 0) {
                ## No projection left
                ## move on to next iteration
                
                I <- I + 1
                
                winfilepre <-
                    paste(tempprefix, "win_", WINSHIFT, ".", CHR, ".", I,
                          sep='')

                next
            }

            wt0 <- rep(NA, Nq)
    
            for (Il in 1:nLambdaPT) {
            
                lambda.lo <- lambda.q[Il]
                lambda.hi <- lambda.q[Il+1]
                in.lambda.bin <- lambda0 > lambda.lo & lambda0 <= lambda.hi
            
                for (Je in 1:nEtaPT) {
                
                    betahatH.lo <- betahatH.q[Je, Il]
                    betahatH.hi <- betahatH.q[Je+1, Il]
                    in.betahatH.bin <-
                        (in.lambda.bin & 
                         abs(etahat0) > betahatH.lo &
                         abs(etahat0) <= betahatH.hi)
                
                    if (any(in.betahatH.bin)) {
                        wt0[in.betahatH.bin] <- PTwt[Il, Je, 1]
                    }
                }
            }
            
            if (any(etahat0 == 0)) {
                wt0[etahat0 == 0] <- 0
            }
            
            ASSERT(all(!is.na(wt0)))

#       Compared to manuscript, we did not scale qX0 with lambda^(-1/2), 
#       thus no need to scale here again, wt0 includes the factor already.
#       etahat0.adj <- etahat0 * wt0 / sqrt(lambda0)
            etahat0.adj <- etahat0 * wt0 

            wt.betahat <- c(wt.betahat, Q0 %*% as.matrix(etahat0.adj))

            ASSERT(all(!is.na(wt.betahat)))

        ## move on to next iteration
            I <- I + 1

            winfilepre <-
                paste(tempprefix, "win_", WINSHIFT, ".", CHR, ".", I, sep='')
        }

        ## pad
        M.written <- length(wt.betahat)

        if ((M.chr - M.written) > 0) {
            cat("Pad ", (M.chr - M.written),
                " SNPs with 0 at the end of chrom\n")
    
            wt.betahat <- c(wt.betahat, rep(0, M.chr - M.written))
        }
    
        ASSERT(M.chr == length(wt.betahat))


    ## add tail betahats
        tailbetahatfile <- paste(tempprefix, "tail_betahat.", CHR, ".table",
                                 sep='')

        if (file.exists(tailbetahatfile)) {
    
            betahat.tail.chr <-
                read.delim(tailbetahatfile, header=FALSE, sep="\t")[, 1]
            
            ASSERT(length(betahat.tail.chr) == M.chr)

            wt.betahat <- wt.betahat + betahat.tail.chr * PTwt.tail

        }

# se: discovery af 
#    wt.betahat <- wt.betahat / se[snpIdx0 + c(1:M.chr)]

# se: training af

        ASSERT(length(tr.se.chr) == M.chr)

        wt.betahat <- wt.betahat / tr.se.chr

    ## write.table(data.frame(betahat=wt.betahat),
    ##             file=paste(traindir, "/", traintag, ".win_", WINSHIFT,
    ##                 ".adjbetahat.chrom", CHR, ".txt", sep=''),
    ##             quote=FALSE, row.names=FALSE, col.names=FALSE)

        filename <- paste(tempprefix, "/", traintag, ".win_", WINSHIFT,
                          ".adjbetahat.chrom", CHR, ".txt", sep='')
        
        cat("Saving reweighted snpeffs:", filename, "...")
        
        write.table(data.frame(betahat=wt.betahat),
                    file=filename,
                    quote=FALSE, row.names=FALSE, col.names=FALSE)

        cat("OK\n")
    }
}

cat("Done\n")
    