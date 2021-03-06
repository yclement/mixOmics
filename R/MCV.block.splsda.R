#############################################################################################################
# Authors:
#   Kim-Anh Le Cao, The University of Queensland, The University of Queensland Diamantina Institute, Translational Research Institute, Brisbane, QLD
#   Francois Bartolo, Institut National des Sciences Appliquees et Institut de Mathematiques, Universite de Toulouse et CNRS (UMR 5219), France
#   Florian Rohart, The University of Queensland, The University of Queensland Diamantina Institute, Translational Research Institute, Brisbane, QLD
#
# created: 18-09-2017
# last modified: 05-10-2017
#
# Copyright (C) 2015
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#############################################################################################################


# ========================================================================================================
# tune.block.splsda: chose the optimal number of parameters per component on a splsda method
# ========================================================================================================

# X: a list of data sets (called 'blocks') matching on the same samples. Data in the list should be arranged in samples x variables, with samples order matching in all data sets. \code{NA}s are not allowed.
# Y: a factor or a class vector for the discrete outcome.
# validation: Mfold or loo cross validation
# folds: if validation = Mfold, how many folds?
# nrepeat: number of replication of the Mfold process
# ncomp: the number of components to include in the model. Default to 1.
# choice.keepX: a list, each choice.keepX[[i]] is a vector giving keepX on the components that were already tuned for block i
# test.keepX: grid of keepX among which to chose the optimal one
# measure: one of c("overall","BER"). Accuracy measure used in the cross validation processs
# weighted: optimise the weighted or not-weighted prediction
# dist: distance to classify samples. see predict
# scheme: the input scheme, one of "horst", "factorial" or ""centroid". Default to "centroid"
# design: the input design.
# init: intialisation of the algorithm, one of "svd" or "svd.single". Default to "svd"
# tol: Convergence stopping value.
# max.iter: integer, the maximum number of iterations.
# near.zero.var: boolean, see the internal \code{\link{nearZeroVar}} function (should be set to TRUE in particular for data with many zero values). Setting this argument to FALSE (when appropriate) will speed up the computations
# progressBar: show progress,
# cl: if parallel, the clusters
# scale: boleean. If scale = TRUE, each block is standardized to zero means and unit variances (default: TRUE).
# misdata: optional. any missing values in the data? list, misdata[[q]] for each data set
# is.na.A: optional. where are the missing values? list, is.na.A[[q]] for each data set (if misdata[[q]] == TRUE)
# ind.NA: optional. which rows have missing values? list, ind.NA[[q]] for each data set.
# ind.NA.col: optional. which col have missing values? list, ind.NA.col[[q]] for each data set.
# parallel: logical.



MCVfold.block.splsda = function(
X,
Y,
validation,
folds,
nrepeat = 1,
ncomp,
choice.keepX = NULL, # keepX chosen on the first components
test.keepX, # a list of value(keepX) to test on the last component. There needs to be names(test.keepX)
measure = c("overall"), # one of c("overall","BER")
weighted = TRUE, # optimise the weighted or not-weighted prediction
dist = "max.dist",
scheme,
design,
init,
tol,
max.iter = 100,
near.zero.var = FALSE,
progressBar = TRUE,
cl,
scale,
misdata,
is.na.A,
parallel
)
{    #-- checking general input parameters --------------------------------------#
    #---------------------------------------------------------------------------#
    #-- set up a progress bar --#
    if (progressBar ==  TRUE)
    {
        pb = txtProgressBar(style = 3)
        nBar = 1
    } else {
        pb = FALSE
    }
    
    #design = matrix(c(0,1,1,0), ncol = 2, nrow = 2, byrow = TRUE)
    
    if(ncomp>1)
    {
        keepY = rep(nlevels(Y), ncomp-1)
    } else {keepY = NULL}
    
    M = length(folds)
    prediction.comp = class.comp = list()
    for(ijk in dist)
    class.comp[[ijk]] = array(0, c(nrow(X[[1]]), nrepeat, nrow(expand.grid(test.keepX))))# prediction of all samples for each test.keepX and  nrep at comp fixed
    folds.input = folds
    for(nrep in 1:nrepeat)
    {
        # we don't record all the prediction for all fold and all blocks, too much data

        #prediction.comp[[nrep]] = array(0, c(nrow(X), nlevels(Y), length(test.keepX)), dimnames = list(rownames(X), levels(Y), names(test.keepX)))
        #rownames(prediction.comp[[nrep]]) = rownames(X)
        #colnames(prediction.comp[[nrep]]) = levels(Y)

        n = nrow(X[[1]])
        repeated.measure = 1:n
        #if (!is.null(multilevel))
        #{
        #    repeated.measure = multilevel[,1]
        #    n = length(unique(repeated.measure)) # unique observation: we put every observation of the same "sample" in the either the training or test set
        #}
        
        
        #-- define the folds --#
        if (validation ==  "Mfold")
        {
            
            if (nrep > 1) # reinitialise the folds
            folds = folds.input
            
            if (is.null(folds) || !is.numeric(folds) || folds < 2 || folds > n)
            {
                stop("Invalid number of folds.")
            } else {
                M = round(folds)
                #if (is.null(multilevel))
                #{
                    temp = stratified.subsampling(Y, folds = M)
                    folds = temp$SAMPLE
                    if(temp$stop > 0 & nrep == 1) # to show only once
                    warning("At least one class is not represented in one fold, which may unbalance the error rate.\n  Consider a number of folds lower than the minimum in table(Y): ", min(table(Y)))
                    #} else {
                    #folds = split(sample(1:n), rep(1:M, length = n)) # needs to have all repeated samples in the same fold
                    #}
            }
        } else if (validation ==  "loo") {
            folds = split(1:n, rep(1:n, length = n))
            M = n
        }
        
        M = length(folds)
        
        error.sw = matrix(0,nrow = M, ncol = length(test.keepX))
        rownames(error.sw) = paste0("fold",1:M)
        colnames(error.sw) = names(test.keepX)
        # for the last keepX (i) tested, prediction combined for all M folds so as to extract the error rate per class
        # prediction.all = vector(length = nrow(X))
        # in case the test set only includes one sample, it is better to advise the user to
        # perform loocv
        stop.user = FALSE
        
        #save(list=ls(),file="temp22.Rdata")

        #result.all=list()
        fonction.j.folds =function(j)#for(j in 1:M)
        {
            if (progressBar ==  TRUE)
            setTxtProgressBar(pb, (M*(nrep-1)+j-1)/(M*nrepeat))
            
            #print(j)
            #set up leave out samples.
            omit = which(repeated.measure %in% folds[[j]] == TRUE)
            
            # get training and test set
            X.train = lapply(X, function(x){x[-omit, ]})
            Y.train = Y[-omit]
            Y.train.mat = unmap(Y.train)
            Q = ncol(Y.train.mat)
            colnames(Y.train.mat) = levels(Y.train)
            rownames(Y.train.mat) = rownames(X.train[[1]])
            X.test = lapply(X, function(x){x[omit, , drop = FALSE]}) #matrix(X[omit, ], nrow = length(omit)) #removed to keep the colnames in X.test
            Y.test = Y[omit]


            #---------------------------------------#
            #-- near.zero.var ----------------------#
            remove = vector("list",length=length(X))
            # first remove variables with no variance inside each X.train/X.test
            #var.train = colVars(X.train, na.rm=TRUE)#apply(X.train, 2, var)
            var.train = lapply(X.train, function(x){colVars(x, na.rm=TRUE)})
            for(q in 1:length(X))
            {
                ind.var = which(var.train[[q]] == 0)
                if (length(ind.var) > 0)
                {
                    remove[[q]] = c(remove[[q]], colnames(X.train[[q]])[ind.var])

                    X.train[[q]] = X.train[[q]][, -c(ind.var),drop = FALSE]
                    X.test[[q]] = X.test[[q]][, -c(ind.var),drop = FALSE]
                    
                    # reduce choice.keepX and test.keepX if needed
                    if (any(choice.keepX[[q]] > ncol(X.train[[q]])))
                    choice.keepX[[q]][which(choice.keepX[[q]]>ncol(X.train[[q]]))] = ncol(X.train[[q]])
                    
                    # reduce test.keepX if needed
                    if (any(test.keepX[[q]] > ncol(X.train[[q]])))
                    test.keepX[[q]][which(test.keepX[[q]]>ncol(X.train[[q]]))] = ncol(X.train[[q]])
                    
                }
            }
            
            # near zero var on X.train
            if(near.zero.var == TRUE)
            {
                nzv.A = lapply(X.train, nearZeroVar)
                for(q in 1:length(X.train))
                {
                    if (length(nzv.A[[q]]$Position) > 0)
                    {
                        names.remove.X = colnames(X.train[[q]])[nzv.A[[q]]$Position]
                        remove[[q]] = c(remove[[q]], names.remove.X)

                        X.train[[q]] = X.train[[q]][, -nzv.A[[q]]$Position, drop=FALSE]
                        X.test[[q]] = X.test[[q]][, -nzv.A[[q]]$Position,drop = FALSE]
                        
                        #if (verbose)
                        #warning("Zero- or near-zero variance predictors.\n Reset predictors matrix to not near-zero variance predictors.\n See $nzv for problematic predictors.")
                        if (ncol(X.train[[q]]) == 0)
                        stop(paste0("No more variables in",X.train[[q]]))
                        
                        #need to check that the keepA[[q]] is now not higher than ncol(A[[q]])
                        if (any(test.keepX[[q]] > ncol(X.train[[q]])))
                        test.keepX[[q]][which(test.keepX[[q]]>ncol(X.train[[q]]))] = ncol(X.train[[q]])
                    }
                }
            }
            
            #-- near.zero.var ----------------------#
            #---------------------------------------#
            
            
            #------------------------------------------#
            # split the NA in training and testing
            if(any(misdata))
            {
                
                is.na.A.train = is.na.A.test = ind.NA.train = ind.NA.col.train = vector("list", length = length(X))

                for(q in 1:length(X))
                {
                    if(misdata[q])
                    {
                        if(length(remove[[q]])>0){
                            ind.remove = which(colnames(X[[q]]) %in% remove[[q]])
                            is.na.A.train[[q]] = is.na.A[[q]][-omit, -ind.remove, drop=FALSE]
                            is.na.A.test[[q]] = is.na.A[[q]][omit, -ind.remove, drop=FALSE]
                        } else {
                            is.na.A.train[[q]] = is.na.A[[q]][-omit, , drop=FALSE]
                            is.na.A.test[[q]] = is.na.A[[q]][omit, , drop=FALSE]
                        }
                        temp = which(is.na.A.train[[q]], arr.ind=TRUE)
                        ind.NA.train[[q]] = unique(temp[,1])
                        ind.NA.col.train[[q]] = unique(temp[,2])
                    }
                }
                names(is.na.A.train) = names(is.na.A.test) = names(ind.NA.train) = names(ind.NA.col.train) = names(is.na.A)
                
                
                if(FALSE){
                    is.na.A.train = ind.NA.train = ind.NA.col.train = vector("list", length = length(X))
                    
                    is.na.A.train= lapply(is.na.A, function(x){x[-omit,, drop=FALSE]})
                    is.na.A.test = lapply(is.na.A, function(x){x[omit,,drop=FALSE]})
                    for(q in 1:length(X))
                    {
                        if(misdata[q])
                        {
                            
                            temp = which(is.na.A.train[[q]], arr.ind=TRUE)
                            ind.NA.train[[q]] = unique(temp[,1])
                            ind.NA.col.train[[q]] = unique(temp[,2])
                            #ind.NA.train[[q]] = which(apply(is.na.A.train[[q]], 1, sum) > 0) # calculated only once
                            #ind.NA.test = which(apply(is.na.A.test, 1, sum) > 0) # calculated only once
                            #ind.NA.col.train[[q]] = which(apply(is.na.A.train[[q]], 2, sum) > 0) # calculated only once
                        }
                    }
                }
            } else {
                is.na.A.train = is.na.A.test = NULL
                ind.NA.train = NULL
                ind.NA.col.train = NULL
            }

            # split the NA in training and testing
            #------------------------------------------#


            #save(list=ls(), file="temp2.Rdata")
            #stop("blaa")
            
            #prediction.comp.j = array(0, c(length(omit), nlevels(Y), length(test.keepX)), dimnames = list(rownames(X.test), levels(Y), names(test.keepX)))
            is.na.A.temp = ind.NA.temp = ind.NA.col.temp = vector("list", length = length(X)+1) # inside wrapper.mint.block, X and Y are combined, so the ind.NA need  length(X)+1
            is.na.A.temp[1:length(X)] = is.na.A.train
            ind.NA.temp[1:length(X)] = ind.NA.train
            ind.NA.col.temp[1:length(X)] = ind.NA.col.train
                        
            # shape input for `internal_mint.block' (keepA, test.keepA, etc)
            #print(system.time(
            result <- suppressMessages(internal_wrapper.mint.block(X=X.train, Y=Y.train.mat, study=factor(rep(1,length(Y.train))), ncomp=ncomp,
            keepX=choice.keepX, keepY=rep(ncol(Y.train.mat), ncomp-1), test.keepX=test.keepX, test.keepY=ncol(Y.train.mat),
            mode="regression", scale=scale, near.zero.var=near.zero.var, design=design,
            max.iter=max.iter, scheme =scheme, init=init, tol=tol,
            misdata = misdata, is.na.A = is.na.A.temp, ind.NA = ind.NA.temp,
            ind.NA.col = ind.NA.col.temp, all.outputs=FALSE))
            #))
            
            # `result' returns loadings and variates for all test.keepX on the ncomp component
            
            # need to find the best keepX/keepY among all the tested models
            #save(list=ls(),file="temp.Rdata")
            
            # we prep the test set for the successive prediction: scale and is.na.newdata
            # scale X.test
            #time0=proc.time()
            ind.match = 1:length(X.train)# for missing blocks in predict.R
            if (!is.null(attr(result$A[[1]], "scaled:center")))
            X.test[which(!is.na(ind.match))] = lapply(which(!is.na(ind.match)), function(x){sweep(X.test[[x]], 2, STATS = attr(result$A[[x]], "scaled:center"))})
            if (scale)
            X.test[which(!is.na(ind.match))] = lapply(which(!is.na(ind.match)), function(x){sweep(X.test[[x]], 2, FUN = "/", STATS = attr(result$A[[x]], "scaled:scale"))})
            
            means.Y = matrix(attr(result$A[[result$indY]], "scaled:center"),nrow=nrow(X.test[[1]]),ncol=Q,byrow=TRUE);
            if (scale)
            {sigma.Y = matrix(attr(result$A[[result$indY]], "scaled:scale"),nrow=nrow(X.test[[1]]),ncol=Q,byrow=TRUE)}else{sigma.Y=matrix(1,nrow=nrow(X.test[[1]]),ncol=Q)}
            
            names(X.test)=names(X.train)
            
            # record prediction results for each test.keepX
            keepA = result$keepA
            test.keepA = keepA[[ncomp]]
            
            class.comp.j = list()
            for(ijk in dist)
            class.comp.j[[ijk]] = matrix(0, nrow = length(omit), ncol = nrow(test.keepA))# prediction of all samples for each test.keepX and  nrep at comp fixed
            
            
            # creates temporary block.splsda object to use the predict function
            class(result) = c("block.splsda", "block.spls", "sgccda", "sgcca", "DA")#c("splsda","spls","DA")
            
            result$X = result$A[-result$indY]
            result$ind.mat = result$A[result$indY][[1]]
            result$Y = factor(Y.train)

            #save variates and loadings for all test.keepA
            result.temp = list(variates = result$variates, loadings = result$loadings)

            #time2 = proc.time()
            for(i in 1:nrow(test.keepA))
            {
                #print(i)
                
                # only pick the loadings and variates relevant to that test.keepX
                
                names.to.pick = NULL
                if(ncomp>1)
                names.to.pick = unlist(lapply(1:(ncomp-1), function(x){
                    paste(paste0("comp",x),apply(keepA[[x]],1,function(x) paste(x,collapse="_")), sep=":")
                    
                }))
                
                names.to.pick.ncomp = paste(paste0("comp",ncomp),paste(as.numeric(keepA[[ncomp]][i,]),collapse="_"), sep=":")
                names.to.pick = c(names.to.pick, names.to.pick.ncomp)
                
                
                result$variates = lapply(result.temp$variates, function(x){if(ncol(x)!=ncomp) {x[,colnames(x)%in%names.to.pick, drop=FALSE]}else{x}})
                result$loadings = lapply(result.temp$loadings, function(x){if(ncol(x)!=ncomp) {x[,colnames(x)%in%names.to.pick, drop=FALSE]}else{x}})
                
                result$weights = get.weights(result$variates, indY = result$indY)

                # do the prediction, we are passing to the function some invisible parameters:
                # the scaled newdata and the missing values
                #print(system.time(
                test.predict.sw <- predict.block.spls(result, newdata.scale = X.test, dist = dist, misdata.all=misdata, is.na.X = is.na.A.train, is.na.newdata = is.na.A.test, noAveragePredict=FALSE)
                #))
                #prediction.comp.j[, , i] =  test.predict.sw$predict[, , ncomp]
                if(weighted ==TRUE) #WeightedVote
                {
                    for(ijk in dist)
                    class.comp.j[[ijk]][, i] =  test.predict.sw$WeightedVote[[ijk]][, ncomp] #levels(Y)[test.predict.sw$class[[ijk]][, ncomp]]
                } else {#MajorityVote
                    for(ijk in dist)
                    class.comp.j[[ijk]][, i] =  test.predict.sw$MajorityVote[[ijk]][, ncomp] #levels(Y)[test.predict.sw$class[[ijk]][, ncomp]]

                }
            } # end i

            return(list(class.comp.j = class.comp.j, omit = omit, keepA = keepA))#, prediction.comp.j = prediction.comp.j))
            #result.all[[j]] = list(class.comp.j = class.comp.j, features = features.j, omit = omit, keepA = keepA)
        } # end fonction.j.folds
        


        if (parallel == TRUE)
        {
            clusterEvalQ(cl, library(mixOmics))
            clusterExport(cl, ls(), envir=environment())
           result.all = parLapply(cl, 1: M, fonction.j.folds)
        } else {
           result.all = lapply(1: M, fonction.j.folds)
        }

        keepA = result.all[[1]]$keepA
        test.keepA = keepA[[ncomp]]

        # combine the results
        for(j in 1:M)
        {
            omit = result.all[[j]]$omit
            #prediction.comp.j = result[[j]]$prediction.comp.j
            class.comp.j = result.all[[j]]$class.comp.j

            #prediction.comp[[nrep]][omit, , ] = prediction.comp.j
            for(ijk in dist)
            class.comp[[ijk]][omit,nrep, ] = class.comp.j[[ijk]]
        }
        
        if (progressBar ==  TRUE)
        setTxtProgressBar(pb, (M*nrep)/(M*nrepeat))
        
    } #end nrep 1:nrepeat

    #names(prediction.comp) =
    # class.comp[[ijk]] is a matrix containing all prediction for test.keepX, all nrepeat and all distance, at comp fixed
    
    keepA.names = apply(test.keepA[,1:length(X)],1,function(x) paste(x,collapse="_"))#, sep=":")
        

    result = list()
    error.mean = error.sd = error.per.class.keepX.opt.comp = keepX.opt = test.keepX.out = mat.error.final = choice.keepX.out = list()
    #save(list=ls(), file="temp22.Rdata")

    if (any(measure == "overall"))
    {
        for(ijk in dist)
        {
            rownames(class.comp[[ijk]]) = rownames(X)
            colnames(class.comp[[ijk]]) = paste0("nrep.", 1:nrepeat)
            dimnames(class.comp[[ijk]])[[3]] = keepA.names
            
            #finding the best keepX depending on the error measure: overall or BER
            # classification error for each nrep and each test.keepX: summing over all samples
            error = apply(class.comp[[ijk]],c(3,2),function(x)
            {
                length(Y) - sum(as.character(Y) == x, na.rm=TRUE)
            })
            #rownames(error) = names(test.keepX)
            #colnames(error) = paste0("nrep.",1:nrepeat)
            
            # we want to average the error per keepX over nrepeat and choose the minimum error
            error.mean[[ijk]] = apply(error,1,mean)/length(Y)
            if (!nrepeat ==  1)
            error.sd[[ijk]] = apply(error,1,sd)/length(Y)
            
            mat.error.final[[ijk]] = error/length(Y)  # percentage of misclassification error for each test.keepX (rows) and each nrepeat (columns)
            
            
            min.error = min(error.mean[[ijk]])
            min.keepX = rownames(error)[which(error.mean[[ijk]] == min.error)] # vector of all keepX combination that gives the minimum error
            
            a = lapply(min.keepX, function(x){as.numeric(strsplit(x, "_")[[1]][1:length(X)])}) #lapply(strsplit(min.keepX,":"), function(x){as.numeric(strsplit(x[2], "_")[[1]][1:length(X)])})
            
            #transform keepX in percentage of variable per dataset, so we choose the minimal overall
            p = sapply(X,ncol)
            percent = sapply(a, function(x) sum(x/p))
            ind.opt = which.min(percent) # we take only one
            a = a[[ind.opt]]# vector of each optimal keepX for all block on component comp.real[comp]
            
            # best keepX
            opt.keepX.comp = as.list(a)
            names(opt.keepX.comp) = names(X)
            
            choice.keepX = lapply(1:length(X), function(x){c(choice.keepX[[x]],opt.keepX.comp[[x]])})
            names(choice.keepX) = names(X)
            
            keepX.opt[[ijk]] = which(error.mean[[ijk]] == min.error)[ind.opt]
            
            
            # confusion matrix for keepX.opt
            error.per.class.keepX.opt.comp[[ijk]] = apply(class.comp[[ijk]][, , keepX.opt[[ijk]], drop = FALSE], 2, function(x)
            {
                conf = get.confusion_matrix(truth = factor(Y), predicted = x)
                out = (apply(conf, 1, sum) - diag(conf)) / summary(Y)
            })
            
            #rownames(error.per.class.keepX.opt.comp[[ijk]]) = levels(Y)
            #colnames(error.per.class.keepX.opt.comp[[ijk]]) = paste0("nrep.", 1:nrepeat)
            
            test.keepX.out[[ijk]] = keepA.names[keepX.opt[[ijk]]]#strsplit(keepA.names[keepX.opt[[ijk]]],":")[[1]][2] # single entry of the keepX for each block
        
            result$"overall"$error.rate.mean = error.mean
            if (!nrepeat ==  1)
            result$"overall"$error.rate.sd = error.sd
            
            result$"overall"$confusion = error.per.class.keepX.opt.comp
            result$"overall"$mat.error.rate = mat.error.final
            result$"overall"$ind.keepX.opt = keepX.opt
            result$"overall"$keepX.opt = test.keepX.out
            result$"overall"$choice.keepX = choice.keepX

        }
    }
    
    if (any(measure ==  "BER"))
    {
        for(ijk in dist)
        {
            rownames(class.comp[[ijk]]) = rownames(X[[1]])
            colnames(class.comp[[ijk]]) = paste0("nrep.", 1:nrepeat)
            dimnames(class.comp[[ijk]])[[3]] = keepA.names
            
            error = apply(class.comp[[ijk]],c(3,2),function(x)
            {
                conf = get.confusion_matrix(truth = factor(Y),predicted = x)
                get.BER(conf)
            })
            rownames(error) = keepA.names
            colnames(error) = paste0("nrep.",1:nrepeat)
            
            # average BER over the nrepeat
            error.mean[[ijk]] = apply(error,1,mean)
            if (!nrepeat ==  1)
            error.sd[[ijk]] = apply(error,1,sd)
            
            mat.error.final[[ijk]] = error  # BER for each test.keepX (rows) and each nrepeat (columns)
            
            
            min.error = min(error.mean[[ijk]])
            min.keepX = rownames(error)[which(error.mean[[ijk]] == min.error)] # vector of all keepX combination that gives the minimum error
            
            a = lapply(min.keepX, function(x){as.numeric(strsplit(x, "_")[[1]][1:length(X)])}) #lapply(strsplit(min.keepX,":"), function(x){as.numeric(strsplit(x[2], "_")[[1]][1:length(X)])})
            
            #transform keepX in percentage of variable per dataset, so we choose the minimal overall
            p = sapply(X,ncol)
            percent = sapply(a, function(x) sum(x/p))
            ind.opt = which.min(percent) # we take only one
            a = a[[ind.opt]]# vector of each optimal keepX for all block on component comp.real[comp]
            
            # best keepX
            opt.keepX.comp = as.list(a)
            names(opt.keepX.comp) = names(X)

            choice.keepX = lapply(1:length(X), function(x){c(choice.keepX[[x]],opt.keepX.comp[[x]])})
            names(choice.keepX) = names(X)

            keepX.opt[[ijk]] = which(error.mean[[ijk]] == min.error)[ind.opt]
            
            # confusion matrix for keepX.opt
            error.per.class.keepX.opt.comp[[ijk]] = apply(class.comp[[ijk]][, , keepX.opt[[ijk]], drop = FALSE], 2, function(x)
            {
                conf = get.confusion_matrix(truth = factor(Y), predicted = x)
                out = (apply(conf, 1, sum) - diag(conf)) / summary(Y)
            })
            
            rownames(error.per.class.keepX.opt.comp[[ijk]]) = levels(Y)
            colnames(error.per.class.keepX.opt.comp[[ijk]]) = paste0("nrep.", 1:nrepeat)
            
            test.keepX.out[[ijk]] = keepA.names[keepX.opt[[ijk]]]#strsplit(keepA.names[keepX.opt[[ijk]]],":")[[1]][2] # single entry of the keepX for each block

            result$"BER"$error.rate.mean = error.mean
            if (!nrepeat ==  1)
            result$"BER"$error.rate.sd = error.sd
            
            result$"BER"$confusion = error.per.class.keepX.opt.comp
            result$"BER"$mat.error.rate = mat.error.final
            result$"BER"$ind.keepX.opt = keepX.opt
            result$"BER"$keepX.opt = test.keepX.out
            result$"BER"$choice.keepX = choice.keepX
        }
        
        
    }
    
    #result$prediction.comp = prediction.comp
    result$class.comp = class.comp
    return(result)
}
