

#include "matrix.h"
#include "mex.h"
#include "backward_alg_omp.h"
#include "forward_alg_omp.h"
#include "stdio.h"
#include "omp.h"


/* Implemented with C OpenMP library for multiple process.
 *
 * compile with:
 *      mex compute_topk_omp.c forward_alg_omp.c backward_alg_omp.c  CFLAGS="\$CFLAGS -fopenmp" LDFLAGS="\$LDFLAGS -fopenmp" CC="/usr/local/bin/gcc -std=c99"
 *
 * use in MATLAB:
 */

void mexFunction( int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[] )
{
    //printf("+++>compute_topk\n");
    /* DEFINE INPUT AND OUTPUT */
    #define IN_gradient         prhs[0]
    #define IN_K                prhs[1]
    #define IN_E                prhs[2]
    #define IN_node_degree      prhs[3]
    #define OUT_Ymax            plhs[0]
    #define OUT_YmaxVal         plhs[1]
    
    /* INPUT */
    // gradient
    double * gradient_i;
    gradient_i = mxGetPr(IN_gradient);
    // K
    int K;
    K = mxGetScalar(IN_K);
    // E
    double * E;
    E = mxGetPr(IN_E);
    // node_degree
    double * node_degree;
    node_degree = mxGetPr(IN_node_degree);
    // mm
    int E_nrow = mxGetM(IN_E);
    int gradient_len = mxGetM(IN_gradient);
    int mm;
    mm = gradient_len/4/E_nrow;
    // nlabel
    int nlabel;
    nlabel = mxGetN(IN_node_degree);
    // MIN_GRADIENT_VAL & local copy of gradient
    
    double min_gradient_val;
    double * gradient;
    gradient = (double *) malloc (sizeof(double) * gradient_len);
    min_gradient_val = 1000000000000;
    
    for(int ii=0;ii<gradient_len;ii++)
    {
        gradient[ii] = gradient_i[ii];
        if(gradient_i[ii]<min_gradient_val)
        {min_gradient_val = gradient_i[ii];}
    }
    for(int ii=0;ii<gradient_len;ii++)
    {
        gradient[ii] = gradient[ii]- min_gradient_val+0.00001;
    }
    
    // Ymax
    double * Ymax;
    OUT_Ymax = mxCreateDoubleMatrix(mm,K*nlabel,mxREAL);
    Ymax = mxGetPr(OUT_Ymax);
    // YmaxVal
    double * YmaxVal;
    OUT_YmaxVal = mxCreateDoubleMatrix(mm,K,mxREAL);
    YmaxVal = mxGetPr(OUT_YmaxVal);
    // MAX_NODE_DEGREE
    int max_node_degree;
    max_node_degree = 0;
    for(int ii=0;ii<nlabel;ii++)
    {
        if(max_node_degree<node_degree[ii])
        {max_node_degree = node_degree[ii];}
    }
    
    // OMP LOOP THROUGH EXAMPLES
    int nn = 100;
    int nworker = (mm-2)/nn;
    //printf("data: %d worker: %d\n", mm,nworker);
    if(nworker <1){nworker=1;};
    int * start_pos = (int *) malloc (sizeof(int) * (nworker));
    int * stop_pos = (int *) malloc (sizeof(int) * (nworker));
    start_pos[0]=0;
    stop_pos[0]=nn;
    for(int ii=1;ii<nworker;ii++)
    {
        start_pos[ii]=ii*nn;
        stop_pos[ii]=(ii+1)*nn;
    }
    stop_pos[nworker-1]=mm;
    int share_i;
    
    //#pragma omp parallel for private(share_i)
    for(share_i=0;share_i<nworker;share_i++)
    {
        //printf("--->%d %d %d\n",share_i, start_pos[share_i],stop_pos[share_i]);
        int  tid = omp_get_thread_num();
        
    for(int training_i=start_pos[share_i];training_i<stop_pos[share_i];training_i++)
    {
        //printf("%d %d \n", share_i,training_i);
        // GET TRAINING GRADIENT
        double * training_gradient;
        training_gradient = (double *) malloc (sizeof(double) * 4 * E_nrow);
        //printm(gradient,36,1);
        for(int ii=0;ii<E_nrow*4;ii++)
        {training_gradient[ii] = gradient[ii+training_i*4*E_nrow];}
        
        // FORWARD ALGORITHM TO GET P_NODE AND T_NODE
        double * results;
        results = forward_alg_omp(training_gradient, K, E, nlabel, node_degree, max_node_degree);
        double * P_node;
        double * T_node;
        P_node = (double *) malloc (sizeof(double) * K*nlabel*2*(max_node_degree+1));
        T_node = (double *) malloc (sizeof(double) * K*nlabel*2*(max_node_degree+1));
        for(int ii=0;ii<K*nlabel;ii++)
        {
            for(int jj=0;jj<2*(max_node_degree+1);jj++)
            {
                P_node[ii+jj*K*nlabel] = results[ii+jj*K*nlabel*2];
            }
        }
        for(int ii=0;ii<K*nlabel;ii++)
        {
            for(int jj=0;jj<2*(max_node_degree+1);jj++)
            {
                T_node[ii+jj*K*nlabel] = results[ii+K*nlabel+jj*K*nlabel*2];
            }
        }
        free(results);

        
        // BACKWARD ALGORITHM TO GET MULTILABEL
        results = backward_alg_omp(P_node, T_node, K, E, nlabel, node_degree, max_node_degree);
        for(int ii=0;ii<K*nlabel;ii++)
        {
            Ymax[training_i+ii*mm] = results[ii];
        }
        for(int ii=0;ii<K;ii++)
        {
            YmaxVal[training_i+ii*mm] = results[ii+K*nlabel];
        }
        free(results);

        
        free(T_node);
        free(P_node);
        free(training_gradient);
    } 
        
    }
    
    for(int ii=0;ii<K*mm;ii++)
    {YmaxVal[ii] = YmaxVal[ii]+min_gradient_val*(nlabel-1);}   
   
    free(gradient);
}
