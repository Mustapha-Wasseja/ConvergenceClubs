#' Merge convergence clubs
#'
#' Merges a list of clubs created with the function findClubs
#' by either Phillips and Sul method or von Lyncker and Thoennessen procedure.
#'
#'
#' @param clubs an object of class \code{convergence.clubs} (created by findClubs function)
#' @param time_trim a numeric value between 0 and 1, representing the portion of
#' time periods to trim when running log t regression model; if omitted, the same
#' value used for \code{clubs} is used.
#' @param mergeMethod character string indicating the merging method to use. Methods
#' available are \code{"PS"} for Phillips and Sul (2009) and \code{"vLT"} for
#' von Lyncker and Thoennessen (2017).
#' @param mergeDivergent logical, if TRUE, indicates that merging of divergent units
#' should be tried.
#' @param threshold a numeric value indicating the threshold to be used with the t-test.
#' @param estar a numeric value indicating the threshold \eqn{e^*}{e*} to test
#' if divergent units may be included in one of the new convergence clubs.
#' To be used only if \code{mergeDivergent=TRUE}
#'
#'
#'
#' @return Ad object of class \code{convergence.clubs}, containing a list of
#' Convergence Clubs, for each club a list is return with the
#' following objects: \code{id}, a vector containing the row indices
#' of the units in the club; \code{model}, a list containing information
#' about the model used to run the t-test on the units in the club;
#' \code{unit_names}, a vector containing the names of the units of the club (optional,
#' only included if parameter \code{unit_names} is given)
#'
#'
#' @details Phillips and Sul (2009) suggest a "club merging algorithm" to avoid
#' over determination due to the selection of the parameter \eqn{c^*}{c*}.
#' This algorithm suggests to merge for adjacent groups. In particular, it works as follows:
#' \enumerate{
#'     \item Take the first two groups detected in the basic clustering mechanism
#'     and run the log-t test. If the t-statistic is larger than -1.65,
#'     these groups together form a new convergence club;
#'     \item Repeat the test adding the next group and continue until the
#'     basic condition (t-statistic > -1.65) holds;
#'     \item If convergence hypothesis is rejected, conclude that all previous groups
#'     converge, except the last one. Hence, start again the test merging algorithm
#'     beginning from the group for which the hypothesis of convergence did not hold.
#' }
#' On the other hand, von Lyncker and Thoennessen (2017), propose a modified version
#' of the club merging algorithm that works as follows:
#'         \enumerate{
#'             \item Take all the groups detected in the basic clustering mechanism (P)
#'             and run the t-test for adjacent groups, obtaining a (M × 1) vector
#'             of convergence test statistics t (where \eqn{M = P - 1} and
#'             \eqn{m = 1, \dots, M}{m = 1, ..., M});
#'             \item Merge for adjacent groups starting from the first, under the
#'             conditions \eqn{t(m) > -1.65} and \eqn{t(m) > t(m+1)}.
#'             In particular, if both conditions hold, the two clubs determining
#'             \eqn{t(m)} are merged and the algorithm starts again from step 1,
#'             otherwise it continues for all following pairs;
#'             \item For the last element of vector M (the value of the last two clubs)
#'             the only condition required for merging is \eqn{t(m=M) > -1.65}.
#'         }
#'
#'
#'
#'
#' @references
#' Phillips, P. C.; Sul, D., 2007. Transition modeling and econometric convergence tests. Econometrica 75 (6), 1771-1855.
#'
#' Phillips, P. C.; Sul, D., 2009. Economic transition and growth. Journal of Applied Econometrics 24 (7), 1153-1185.
#'
#' von Lyncker, K.; Thoennessen, R., 2017. Regional club convergence in the EU: evidence from a panel data analysis.
#' Empirical Economics 52 (2),  525-553
#'
#'
#' @seealso
#' \code{\link{findClubs}}, finds convergence clubs by means of Phillips and Sul clustering procedure.
#'
#' \code{\link{mergeDivergent}}, merges divergent units according to the algorithm proposed by von Lyncker and Thoennessen (2017).
#'
#'
#'
#' @examples
#' data("filteredGDP")
#'
#' # Cluster Countries using GDP from year 1970 to year 2003
#' clubs <- findClubs(filteredGDP, dataCols=2:35, unit_names = 1, refCol=35,
#'                    time_trim = 1/3, cstar = 0, HACmethod = "FQSB")
#' summary(clubs)
#'
#' # Merge clusters
#' mclubs <- mergeClubs(clubs, mergeMethod='PS', mergeDivergent=FALSE)
#' summary(mclubs)
#'
#' mclubs <- mergeClubs(clubs, mergeMethod='vLT', mergeDivergent=FALSE)
#' summary(mclubs)
#'
#' @export


mergeClubs <- function(clubs,
                       time_trim,
                       mergeMethod=c('PS','vLT'),
                       threshold = -1.65,
                       mergeDivergent=FALSE,
                       estar = -1.65){

    ### Check inputs -----------------------------------------------------------
    # HACmethod <- match.arg(HACmethod)
    mergeMethod <- match.arg(mergeMethod)

    if(!inherits(clubs,'convergence.clubs')) stop('clubs must be an object of class convergence.clubs')

    X <- attr(clubs, 'data')
    dataCols <- attr(clubs, 'dataCols')
    refCol <- attr(clubs, 'refCol')
    HACmethod <- attr(clubs, 'HACmethod')

    #length of time series
    t <- length(dataCols)
    if(t < 2) stop('At least two time periods are needed to run this procedure')

    #trimming parameter of the time series
    if(missing(time_trim)){
        time_trim <- attr(clubs, 'time_trim')
    } else{
        if( length(time_trim) > 1 | !is.numeric(time_trim) ) stop('time_trim must be a numeric scalar')
        if( time_trim > 1 | time_trim <= 0 ) stop('invalid value for time_trim; should be a value between 0 and 1')
        if( (t - round(t*time_trim)) < 2) stop('either the number of time periods is too small or the value of time_trim is too high')
    }


    ### Initialise variables ---------------------------------------------------
    ll <- dim(clubs)[1] #number of clubs
    if(ll<2){
        message('The number of clubs is <2, there is nothing to merge.')
        return(clubs)
    }
    #output
    attrib <- attributes(clubs)
    attrib$names <- NULL
    pclub <- list()
    attributes(pclub) <- attrib

    n <- 0
    appendLast <- FALSE
    club_names <- names(clubs)

    ### Merging procedure ------------------------------------------------------
    i <- 1
    while(i<ll){
        units <- clubs[[i]]$id
        cnm <- club_names[i]  #club name
        mod <- list()
        returnNames <- !is.null(attr(clubs, 'unit_names'))
        if(returnNames) unit_names <- clubs[[i]]$unit_names
        for(k in (i+1):ll){
            addunits <- clubs[[k]]$id
            if(returnNames) addnames <- clubs[[k]]$unit_names
            H <- computeH(X[c(units,addunits), dataCols])
            mod <- estimateMod(H, time_trim, HACmethod = HACmethod)
            tvalue <- mod['tvalue']
            #check if a couple of clubs can be merged
            if(tvalue > threshold){
                if(mergeMethod=='vLT' & k <= ll-1){#method by von Lyncker and Rasmus Thoennessen (2016)
                    nextcouple <- c(clubs[[k]]$id,clubs[[k+1]]$id)
                    H <- computeH(X[nextcouple, dataCols])
                    mod2 <- estimateMod(H,time_trim)
                    tvalue2 <- mod2['tvalue']
                    if(tvalue > tvalue2){#if true, merge
                        units <- c(units,addunits)
                        if(returnNames) unit_names <- c(unit_names,addnames)
                        cnm <- c(cnm, club_names[k])
                    }else break
                }else{#method by Phillips and Sul (2009)
                    #if so, store units and names of clubs tested
                    #until now, then keep scanning the club list
                    # and repeat thetest adding another club
                    units <- c(units,addunits)
                    if(returnNames) unit_names <- c(unit_names,addnames)
                    cnm <- c(cnm, club_names[k])
                }
            }else{
                if(k==ll){
                    appendLast <- TRUE
                }
                #end if
                #if not, store in output the highest club (i)
                #and start again from i+1
                break
            }
        }#end for
        i <- k
        n <- n+1
        #store new club
        H <- computeH(X[units, dataCols])
        pclub[[paste('club',n,sep='')]] <- list(clubs = cnm,
                                                id = units,
                                                model = estimateMod(H, time_trim, HACmethod = HACmethod)
        )
        if(returnNames) pclub[[paste('club',n,sep='')]]$unit_names <- unit_names
        if(appendLast){
            pclub[[paste('club',n+1,sep='')]] <- list(clubs = club_names[ll],
                                                      id    = clubs[[ll]]$id,
                                                      model = clubs[[ll]]$model
            )
            if(returnNames) pclub[[paste('club',n+1,sep='')]]$unit_names <- clubs[[ll]]$unit_names
        }
    }
    pclub$divergent <- clubs$divergent
    if(mergeDivergent){
        return(mergeDivergent(pclub, time_trim, estar))
    }else return(pclub)
}
